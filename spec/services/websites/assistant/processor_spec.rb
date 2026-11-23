# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Assistant::Processor do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }
  let!(:website) { create(:website, customer: customer) }
  let!(:home) { create(:website_page, :home, website: website, customer: customer, position: 0) }

  before { enable_module!("website", customer) }

  def document(pages, reply: "Built your pages.")
    { intent: "apply_website", reply: reply, pages: pages }.to_json
  end

  def run(text, chat: nil, write_guard: nil, customer: self.customer, conversation: self.conversation)
    described_class.call(text: text, customer: customer, conversation: conversation, chat: chat, write_guard: write_guard)
  end

  def t(key, **options)
    I18n.t("ai_assistant.assistant.website.#{key}", **options)
  end

  def statement(headline = "Baked daily since 1998")
    { "type" => "statement", "props" => { "headline" => headline } }
  end

  def hero(visual)
    { "type" => "hero_split", "props" => { "headline" => "Fresh bread", "visual_url" => visual } }
  end

  def attach_upload(filename = "shop.png", to: conversation)
    message = create(:ai_assistant_message, conversation: to, customer: to.customer)
    Current.set(customer: to.customer) do
      message.images.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/test.png")),
        filename: filename,
        content_type: "image/png"
      )
    end
    message.images.attachments.max_by(&:id)
  end

  def token(attachment)
    "upload:#{attachment.id}"
  end

  def replying(*texts)
    calls = []
    chat = lambda do |messages|
      calls << messages
      { outcome: :success, text: texts[[ calls.size, texts.size ].min - 1] }
    end
    [ chat, calls ]
  end

  describe "creating pages" do
    it "creates drafts after the existing pages and imports placed photos into tenant media" do
      create(:website_page, website: website, customer: customer, slug: "contact", position: 3)
      upload = attach_upload

      result = run(document([
        { "title" => "About", "slug" => "about", "sections" => [ hero(token(upload)) ] },
        { "title" => "Menu", "nav_visible" => false, "home" => true, "published" => true, "sections" => [ statement ] }
      ]))

      expect(result).to have_attributes(status: "complete", intent: "apply_website", applied: true,
                                        created: %w[About Menu], updated: [])
      about, menu = result.pages
      expect(about.reload).to have_attributes(title: "About", slug: "about", published: false, home: false, position: 4,
                                              customer_id: customer.id, website_id: website.id)
      expect(menu.reload).to have_attributes(slug: "menu", published: false, home: false, nav_visible: false, position: 5)

      url = about.sections.first.dig("props", "visual_url")
      expect(url).to match(%r{\A/#{customer.id}/site/media/[^/]+\z})
      media = ActiveStorage::Blob.find_signed(url.split("/").last)
      expect(media.customer_id).to eq(customer.id)
      expect(media.metadata["assistant_source_blob_id"]).to eq(upload.blob_id)

      expect(result.body).to eq([
        "Built your pages.",
        t("apply_created", names: "About and Menu"),
        t("drafts_note")
      ].join(" "))
      expect(home.reload.home).to be(true)
    end

    it "makes the first new page home when the site has none" do
      home.destroy!

      result = run(document([
        { "title" => "Welcome", "slug" => "welcome", "sections" => [ statement ] },
        { "title" => "Menu", "sections" => [ statement ] }
      ]))

      welcome, menu = result.pages.map(&:reload)
      expect(welcome).to have_attributes(home: true, slug: "", published: false)
      expect(menu).to have_attributes(home: false, slug: "menu")
    end

    it "provisions the website on demand" do
      fresh = create(:customer)
      enable_module!("website", fresh)
      chat_thread = create(:ai_assistant_conversation, customer: fresh)

      result = nil
      expect {
        result = run(document([ { "title" => "Story", "sections" => [ statement ] } ]), customer: fresh, conversation: chat_thread)
      }.to change { Website.where(customer_id: fresh.id).count }.from(0).to(1)

      expect(result.applied).to be(true)
      expect(result.pages.first.website.customer_id).to eq(fresh.id)
    end
  end

  describe "revising pages" do
    it "replaces the sections of a draft page named by page_id" do
      draft = create(:website_page, website: website, customer: customer, title: "About", slug: "about",
                                    sections: [ { "id" => "sec_old", "type" => "rich_text", "props" => { "body" => "Old" } } ])

      result = run(document([ { "page_id" => draft.id, "title" => "About us", "sections" => [ statement("New") ] } ]))

      expect(result).to have_attributes(applied: true, created: [], updated: [ "About us" ], pages: [ draft ])
      draft.reload
      expect(draft).to have_attributes(title: "About us", slug: "about", published: false)
      expect(draft.sections.map { |row| row["type"] }).to eq([ "statement" ])
      expect(result.body).to eq([ "Built your pages.", t("apply_updated", names: "About us") ].join(" "))
    end

    it "records what each written page was, so the reply can be undone" do
      draft = create(:website_page, website: website, customer: customer, title: "About", slug: "about",
                                    sections: [ { "id" => "sec_old", "type" => "rich_text", "props" => { "body" => "Old" } } ])
      before = Websites::Assistant::Undo.snapshot(draft)

      result = run(document([
        { "page_id" => draft.id, "title" => "About us", "sections" => [ statement("New") ] },
        { "title" => "Menu", "slug" => "menu", "sections" => [ statement ] }
      ]))

      menu = website.pages.find_by(slug: "menu")
      fingerprint = ->(page) { Websites::Assistant::Undo.fingerprint(page.reload) }
      expect(result.undo).to eq([
        before.merge("fingerprint" => fingerprint.call(draft)),
        { "page_id" => menu.id, "title" => "Menu", "created" => true, "fingerprint" => fingerprint.call(menu) }
      ])
    end

    it "refuses a page published after validation but before the customer write boundary" do
      draft = create(:website_page, website: website, customer: customer, title: "About", slug: "about",
                                    sections: [statement("Current draft")])
      published_state = nil
      allow(PageShortcuts::Collisions).to receive(:with_customer_lock).and_wrap_original do |original, **args, &operation|
        unless published_state
          draft.reload.update!(published: true)
          published_state = draft.reload.attributes.deep_dup
        end
        original.call(**args, &operation)
      end

      result = run(document([{ "page_id" => draft.id, "title" => "AI replacement", "sections" => [statement("AI draft")] }]))

      expect(result).to have_attributes(applied: false, updated: [], pages: [], undo: [])
      expect(result.body).to include(t("errors.page_published", title: "About"))
      expect(draft.reload.attributes).to eq(published_state)
    end

    it "records and restores the latest pre-write state, including edits after validation" do
      draft = create(:website_page, website: website, customer: customer, title: "About", slug: "about",
                                    sections: [statement("Original draft")])
      latest = nil
      allow(PageShortcuts::Collisions).to receive(:with_customer_lock).and_wrap_original do |original, **args, &operation|
        unless latest
          draft.reload.update!(title: "Human revision", slug: "human-revision", nav_visible: false,
                               sections: [statement("Latest human content").merge("id" => "sec_human")])
          latest = Websites::Assistant::Undo.snapshot(draft.reload)
        end
        original.call(**args, &operation)
      end

      result = run(document([{ "page_id" => draft.id, "title" => "AI revision", "sections" => [statement("AI content")] }]))
      expect(result.applied).to be(true)
      expect(result.undo).to eq([latest.merge("fingerprint" => Websites::Assistant::Undo.fingerprint(draft.reload))])
      reply = create(:ai_assistant_message, :assistant, customer: customer, conversation: conversation,
                     metadata: { Websites::Assistant::Undo::KEY => { "pages" => result.undo } })

      expect(Websites::Assistant::Undo.call(message: reply, customer: customer)).to be_success
      expect(Websites::Assistant::Undo.snapshot(draft.reload)).to eq(latest)
    end

    it "rolls back earlier pages when a revision was published before the locked write" do
      draft = create(:website_page, website: website, customer: customer, title: "About", slug: "about",
                                    sections: [statement("Current draft")])
      published = false
      allow(PageShortcuts::Collisions).to receive(:with_customer_lock).and_wrap_original do |original, **args, &operation|
        unless published
          draft.reload.update!(published: true)
          published = true
        end
        original.call(**args, &operation)
      end

      result = run(document([
        { "title" => "New draft", "slug" => "new-draft", "sections" => [statement] },
        { "page_id" => draft.id, "title" => "AI revision", "sections" => [statement("AI content")] }
      ]))

      expect(result).to have_attributes(applied: false, created: [], updated: [], undo: [])
      expect(website.pages.where(slug: "new-draft")).not_to exist
      expect(draft.reload).to have_attributes(title: "About", published: true)
    end

    it "refuses a published page and applies the repair that moves the change to a new draft" do
      published = create(:website_page, :published, website: website, customer: customer, title: "Pricing",
                                                    slug: "pricing", sections: [ statement("Live") ])
      chat, calls = replying(document([ { "title" => "Pricing", "slug" => "pricing-new", "sections" => [ statement("Draft") ] } ]))

      result = nil
      expect {
        result = run(document([ { "page_id" => published.id, "title" => "Pricing", "sections" => [ statement("Draft") ] } ]),
                     chat: chat)
      }.not_to change { published.reload.attributes }

      expect(calls.size).to eq(1)
      repair_turn = calls.first.last[:content]
      expect(repair_turn).to include(AiAssistant::Assistant::Prompt::Document.read("website_repair"))
      expect(repair_turn).to include(t("errors.page_published", title: "Pricing"))
      expect(result).to have_attributes(applied: true, created: [ "Pricing" ])
      expect(result.pages.first.reload).to have_attributes(slug: "pricing-new", published: false)
    end

    it "refuses another tenant's page_id and writes nothing" do
      foreign = create(:website_page, website: create(:website, customer: other_customer), customer: other_customer,
                                      title: "Theirs")

      result = nil
      expect {
        result = run(document([ { "page_id" => foreign.id, "title" => "Mine now", "sections" => [ statement ] } ]))
      }.not_to change(WebsitePage, :count)

      expect(foreign.reload.title).to eq("Theirs")
      expect(result.applied).to be(false)
      expect(result.body).to eq([
        "Built your pages.",
        t("schema_invalid", details: t("errors.page_not_found", id: foreign.id))
      ].join(" "))
    end
  end

  describe "refused documents" do
    def refused(pages)
      result = nil
      expect {
        expect {
          result = run(document(pages))
        }.not_to change(WebsitePage, :count)
      }.not_to change(ActiveStorage::Blob, :count)
      expect(result).to have_attributes(status: "complete", applied: false, created: [], updated: [], pages: [])
      result
    end

    it "refuses an upload token from another conversation" do
      upload = attach_upload(to: create(:ai_assistant_conversation, customer: customer, user: user))

      result = refused([ { "title" => "About", "sections" => [ hero(token(upload)) ] } ])

      expect(result.body).to include(
        t("errors.unknown_upload", title: "About", type: "hero_split", field: "visual_url", token: token(upload))
      )
    end

    it "refuses an upload token from another tenant" do
      upload = attach_upload(to: create(:ai_assistant_conversation, customer: other_customer))

      result = refused([ { "title" => "About", "sections" => [ hero(token(upload)) ] } ])

      expect(result.body).to include(t("errors.unknown_upload", title: "About", type: "hero_split",
                                                                 field: "visual_url", token: token(upload)))
    end

    it "refuses an image URL the model invented" do
      result = refused([ { "title" => "About", "sections" => [ hero("https://cdn.example.com/bakery.jpg") ] } ])

      expect(result.body).to include(t("errors.invalid_image", title: "About", type: "hero_split", field: "visual_url"))
    end

    # Their own site already shows the image, so a lookup that was not scoped
    # to this tenant's pages would accept it.
    it "refuses another tenant's site media, under either tenant's path" do
      theirs = Current.set(customer: other_customer) do
        ActiveStorage::Blob.create_and_upload!(
          io: File.open(Rails.root.join("spec/fixtures/files/test.png")),
          filename: "theirs.png",
          content_type: "image/png"
        )
      end
      their_url = "/#{other_customer.id}/site/media/#{theirs.signed_id}"
      create(:website_page, website: create(:website, customer: other_customer), customer: other_customer,
                            sections: [ hero(their_url) ])

      result = refused([
        { "title" => "About", "sections" => [ hero(their_url) ] },
        { "title" => "Story", "sections" => [ hero("/#{customer.id}/site/media/#{theirs.signed_id}") ] }
      ])

      expect(result.body).to include(
        t("errors.invalid_image", title: "About", type: "hero_split", field: "visual_url"),
        t("errors.invalid_image", title: "Story", type: "hero_split", field: "visual_url")
      )
    end

    it "refuses an unknown section type" do
      result = refused([ { "title" => "About", "sections" => [ { "type" => "carousel", "props" => {} } ] } ])

      expect(result.body).to include(t("errors.unknown_section", title: "About", index: 1, type: "carousel"))
    end

    it "refuses an internal link to a page that does not exist" do
      cta = { "type" => "cta_band", "props" => { "headline" => "Hungry?", "button_href" => "order" } }

      result = refused([ { "title" => "About", "sections" => [ cta ] } ])

      expect(result.body).to include(
        t("errors.unknown_link", title: "About", type: "cta_band", field: "button_href", slug: "order")
      )
    end

    def fail_save_of(title)
      allow(Websites::Activities::SavePage).to receive(:call).and_call_original
      allow(Websites::Activities::SavePage).to receive(:call)
        .with(hash_including(params: hash_including(title: title)))
        .and_return(Websites::Activities::SavePage::Result.new(success?: false, model: WebsitePage.new, errors: ["Slug is taken"]))
    end

    it "refuses a slug another page already uses before writing anything" do
      create(:website_page, website: website, customer: customer, title: "Contact", slug: "contact", position: 1)

      result = refused([ { "title" => "Contact us", "slug" => "contact", "sections" => [ statement ] } ])

      expect(result.body).to include(t("errors.slug_taken", title: "Contact us", slug: "contact"))
    end

    it "rolls the whole document back when one page cannot be saved" do
      fail_save_of("Contact us")

      result = refused([
        { "title" => "Story", "sections" => [ statement ] },
        { "title" => "Contact us", "slug" => "contact", "sections" => [ statement ] }
      ])

      expect(result.body).to include(t("errors.save_failed", title: "Contact us", details: "Slug is taken"))
      expect(WebsitePage.where(website: website, title: "Story")).to be_empty
    end

    it "imports no photo for a document that is rolled back" do
      fail_save_of("Contact us")
      upload = attach_upload

      refused([ { "title" => "Contact us", "slug" => "contact", "sections" => [ hero(token(upload)) ] } ])

      expect(Websites::Activities::ImportMedia.imports_for(customer: customer, blob: upload.blob)).not_to exist
      expect(Websites::Assistant::Uploads.new(conversation: conversation).pending.map(&:token)).to eq([ token(upload) ])
    end

    it "removes the photo it imported when saving the document raises" do
      allow(Websites::Activities::SavePage).to receive(:call).and_raise(ActiveRecord::RecordNotUnique)
      upload = attach_upload

      expect {
        run(document([ { "title" => "Story", "sections" => [ hero(token(upload)) ] } ]))
      }.to raise_error(ActiveRecord::RecordNotUnique)

      expect(Websites::Activities::ImportMedia.imports_for(customer: customer, blob: upload.blob)).not_to exist
    end

    it "removes the photos it already imported when a later import raises" do
      first = attach_upload("shop.png")
      second = attach_upload("oven.png")
      calls = 0
      allow(Websites::Activities::ImportMedia).to receive(:call).and_wrap_original do |original, **args|
        (calls += 1) == 2 ? raise(ActiveStorage::IntegrityError) : original.call(**args)
      end

      expect {
        run(document([ { "title" => "Story", "sections" => [ hero(token(first)), hero(token(second)) ] } ]))
      }.to raise_error(ActiveStorage::IntegrityError)

      expect(calls).to eq(2)
      expect(Websites::Activities::ImportMedia.imports_for(customer: customer, blob: first.blob)).not_to exist
    end

    it "does not take the home page from one set while the model was replying" do
      home.update!(home: false, slug: "old-home")
      allow(Websites::Assistant::SchemaValidator).to receive(:call).and_wrap_original do |original, **args|
        original.call(**args).tap { home.update!(home: true, slug: "") }
      end

      result = run(document([ { "title" => "Welcome", "sections" => [ statement ] } ]))

      expect(result.applied).to be(true)
      expect(home.reload.home).to be(true)
      expect(website.pages.find_by(title: "Welcome")).to have_attributes(home: false, slug: "welcome")
    end
  end

  describe "self-repair" do
    let(:invalid) do
      document([ {
        "title" => "About",
        "sections" => [
          { "type" => "proof_strip", "props" => { "items" => [ { "label" => "Years", "value" => "25" } ] } },
          { "type" => "hero_cinematic", "props" => { "headline" => "Hi", "tone" => "neon" } }
        ]
      } ])
    end

    it "gives up after MAX_REPAIR attempts and reports every error" do
      chat, calls = replying(invalid)

      result = nil
      expect { result = run(invalid, chat: chat) }.not_to change(WebsitePage, :count)

      expect(calls.size).to eq(described_class::MAX_REPAIR)
      expect(result.applied).to be(false)
      expect(result.body).to start_with("Built your pages. ")
      expect(result.body).to include(
        t("errors.array_count", title: "About", type: "proof_strip", field: "items", min: 4, max: 6),
        t("errors.invalid_option", title: "About", type: "hero_cinematic", field: "tone", options: "light, dark")
      )
    end

    it "applies the corrected document" do
      chat, calls = replying(document([ { "title" => "About", "sections" => [ statement ] } ]))

      result = run(invalid, chat: chat)

      expect(calls.size).to eq(1)
      expect(result.applied).to be(true)
      expect(result.pages.first.sections.map { |row| row["type"] }).to eq([ "statement" ])
    end
  end

  describe "placement nudge" do
    let!(:storefront) { attach_upload("storefront.jpg") }
    let!(:chef) { attach_upload("chef.png") }
    let(:partial) { document([ { "title" => "About", "sections" => [ hero(token(storefront)) ] } ]) }

    it "asks once for the unplaced photos, then applies and names what is still left out" do
      chat, calls = replying(partial)

      result = run(partial, chat: chat)

      expect(calls.size).to eq(1)
      expect(calls.first.last[:content]).to include(t("errors.unplaced_uploads", tokens: token(chef)))
      expect(result.applied).to be(true)
      expect(result.body).to end_with(t("unplaced_images", names: "chef.png"))
    end

    it "applies the placement the model returns" do
      team = { "type" => "team_grid", "props" => { "people" => [ { "name" => "Ana", "image_url" => token(chef) } ] } }
      chat, = replying(document([ { "title" => "About", "sections" => [ hero(token(storefront)), team ] } ]))

      result = run(partial, chat: chat)

      expect(result.applied).to be(true)
      expect(result.body).not_to include(t("unplaced_images", names: "chef.png"))
      expect(result.pages.first.sections.last.dig("props", "people", 0, "image_url")).to match(%r{/site/media/})
    end

    it "falls back to the valid document when the nudge produces nothing usable" do
      calls = 0
      chat = lambda do |_messages|
        calls += 1
        { outcome: :error, text: "" }
      end

      result = run(partial, chat: chat)

      expect(calls).to eq(1)
      expect(result.applied).to be(true)
      expect(result.body).to include(t("unplaced_images", names: "chef.png"))
    end

    it "falls back to the valid document when the nudged reply stays broken" do
      broken = document([ { "title" => "About", "sections" => [ hero("https://cdn.example.com/chef.jpg") ] } ])
      chat, calls = replying(broken)

      result = run(partial, chat: chat)

      expect(calls.size).to eq(described_class::MAX_REPAIR)
      expect(result.applied).to be(true)
      expect(result.pages.first.sections.first.dig("props", "visual_url")).to match(%r{/site/media/})
    end

    it "applies without a nudge when there is no chat to repair with" do
      result = run(partial)

      expect(result.applied).to be(true)
      expect(result.body).to include(t("unplaced_images", names: "chef.png"))
    end
  end

  describe "gates" do
    it "answers with a module-disabled message and writes nothing when the Website module is off" do
      thread = create(:ai_assistant_conversation, customer: other_customer)

      result = nil
      expect {
        result = run(document([ { "title" => "About", "sections" => [ statement ] } ]), customer: other_customer,
                                                                                         conversation: thread)
      }.not_to change(Website, :count)

      expect(result).to have_attributes(body: t("module_disabled"), status: "complete", applied: false)
    end

    it "fails on a document that is not valid JSON and writes nothing" do
      website.destroy!

      result = nil
      expect { result = run('{"intent": "apply_website", "reply": ') }.not_to change(Website, :count)

      expect(result).to have_attributes(body: I18n.t("ai_assistant.assistant.extraction_invalid"), status: "failed",
                                        applied: false)
    end
  end

  describe "write guard" do
    it "rechecks the actual generation after acquiring the customer boundary" do
      turn = create(:ai_assistant_message, customer: customer, conversation: conversation)
      generation = AiAssistant::Assistant::GenerationLifecycle.start!(conversation: conversation, user_message: turn)
      AiAssistant::Assistant::GenerationLifecycle.claim!(generation)
      guard = AiAssistant::Assistant::GenerationWriteGuard.new(generation: generation)
      cancelled = false
      allow(PageShortcuts::Collisions).to receive(:with_customer_lock).and_wrap_original do |original, **args, &operation|
        unless cancelled
          AiAssistant::Assistant::GenerationLifecycle.cancel!(conversation: conversation)
          cancelled = true
        end
        original.call(**args, &operation)
      end

      expect {
        run(document([{ "title" => "About", "sections" => [statement] }]), write_guard: guard)
      }.to raise_error(AiAssistant::Assistant::GenerationWriteGuard::Rejected) { |error| expect(error.state).to eq(:cancelled) }
      expect(website.pages.where(title: "About")).not_to exist
    end

    it "runs the write under the guard" do
      guarded = 0
      guard = lambda do |&operation|
        guarded += 1
        operation.call
      end

      result = run(document([ { "title" => "About", "sections" => [ statement ] } ]), write_guard: guard)

      expect(guarded).to eq(1)
      expect(result.applied).to be(true)
    end

    it "rolls a failed document back inside the guard's own transaction" do
      create(:website_page, website: website, customer: customer, slug: "contact", position: 1)
      guard = ->(&operation) { AiAssistant::Conversation.transaction { operation.call } }

      result = nil
      expect {
        result = run(document([
          { "title" => "Story", "sections" => [ statement ] },
          { "title" => "Contact us", "slug" => "contact", "sections" => [ statement ] }
        ]), write_guard: guard)
      }.not_to change(WebsitePage, :count)

      expect(result.applied).to be(false)
    end

    it "lets a rejected generation propagate without writing" do
      upload = attach_upload
      guard = ->(&_operation) { raise AiAssistant::Assistant::GenerationWriteGuard::Rejected, :cancelled }

      expect {
        expect {
          run(document([ { "title" => "About", "sections" => [ hero(token(upload)) ] } ]), write_guard: guard)
        }.to raise_error(AiAssistant::Assistant::GenerationWriteGuard::Rejected)
      }.not_to change { [ WebsitePage.count, ActiveStorage::Blob.count ] }
    end
  end
end
