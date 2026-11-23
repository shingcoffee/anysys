# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::Template, type: :model do
  let_it_be(:customer) { create(:customer) }

  def build_template(**overrides)
    build(:email_template, customer: customer, **overrides)
  end

  def create_template(**overrides)
    create(:email_template, customer: customer, **overrides)
  end

  describe "EDITOR_TYPES" do
    it "contains exactly rich_text and code (builder retired)" do
      expect(described_class::EDITOR_TYPES).to eq(%w[rich_text code])
    end
  end

  describe "rich-text body" do
    it "responds to body (has_rich_text)" do
      expect(build_template).to respond_to(:body)
    end
  end

  describe "pruned attributes" do
    it "does not expose key/template_type/category/variables" do
      t = create_template
      expect(t.attributes.keys).not_to include("key", "template_type", "category", "variables")
    end
  end

  describe "validations" do
    it "is valid with required attributes" do
      expect(build_template).to be_valid
    end

    it "requires customer_id" do
      template = build_template
      template.customer_id = nil
      expect(template).not_to be_valid
    end

    it "requires name" do
      expect(build_template(name: nil)).not_to be_valid
    end

    it "requires subject" do
      expect(build_template(subject: nil)).not_to be_valid
    end

    it "requires body_html" do
      # For a code template with no body_html and no rich-text body, it must be invalid
      expect(build_template(editor_type: "code", body_html: nil)).not_to be_valid
    end

    it "validates editor_type is in allowed values" do
      expect(build_template(editor_type: "code")).to be_valid
      # rich_text derives body_html from the rich-text body, so the body is
      # the source of truth (setting body_html directly is overwritten).
      expect(build_template(editor_type: "rich_text", body: "<p>hi</p>")).to be_valid
      expect(build_template(editor_type: "builder")).not_to be_valid
      expect(build_template(editor_type: "invalid")).not_to be_valid
    end

    it "validates status is in allowed values" do
      expect(build_template(status: "draft")).to be_valid
      expect(build_template(status: "active")).to be_valid
      expect(build_template(status: "retired")).to be_valid
      expect(build_template(status: "invalid")).not_to be_valid
    end
  end

  describe "#sync_body_html!" do
    it "writes ActionText fragment HTML into body_html for rich_text" do
      template = build_template(editor_type: "rich_text", body_html: "stale")
      template.body = "<p>Hello <strong>world</strong> #{platform_token('first_name')}</p>"
      template.sync_body_html!

      expect(template.body_html).to include("Hello")
      expect(template.body_html).to include(platform_token('first_name'))
      expect(template.body_html).not_to include("trix-content")
      expect(template.body_html).not_to include("BEGIN")
    end

    it "does not overwrite authored body_html for code templates" do
      template = build_template(editor_type: "code", body_html: "<p>Authored #{platform_token('email')}</p>")
      template.sync_body_html!
      expect(template.body_html).to eq("<p>Authored #{platform_token('email')}</p>")
    end

    it "persists synced body_html on save for rich_text" do
      template = build_template(editor_type: "rich_text", body_html: "x")
      template.body = "<p>Persisted body</p>"
      template.save!

      expect(template.reload.body_html).to include("Persisted body")
      expect(template.body.to_plain_text).to include("Persisted body")
    end
  end

  describe "sync-on-save (before_validation)" do
    context "rich_text template with a body" do
      it "populates body_html automatically from the rich-text body" do
        template = create_template(editor_type: "code", body_html: "<p>placeholder</p>")
        # Switch to rich_text and assign a body
        template.editor_type = "rich_text"
        template.body        = "<p>Hello #{platform_token('first_name')}</p>"
        template.save!

        expect(template.body_html).to be_present
        expect(template.body_html).to include("Hello")
        expect(template.body_html).to include(platform_token('first_name'))
      end
    end

    context "rich_text template whose body is cleared" do
      it "clears body_html so stale content can't linger (and presence validation fires)" do
        template = create_template(editor_type: "rich_text", body: "<p>Old content</p>")
        expect(template.body_html).to include("Old content")

        template.body = ""
        expect(template.save).to be(false)              # body_html now blank → presence fails
        expect(template.body_html).to eq("")            # stale "Old content" is gone
        expect(template.errors[:body_html]).to be_present
      end
    end

    context "code template" do
      it "keeps the authored body_html unchanged" do
        authored = "<p>My custom HTML {{token}}</p>"
        template = create_template(editor_type: "code", body_html: authored)

        template.reload
        expect(template.body_html).to eq(authored)
      end
    end
  end

  describe "scopes" do
    let!(:active_template)  { create_template(status: "active") }
    let!(:draft_template)   { create_template(status: "draft") }
    let!(:retired_template) { create_template(status: "retired") }

    it ".active returns only active templates" do
      expect(described_class.active).to contain_exactly(active_template)
    end
  end

  describe "#active?" do
    it "returns true when status is active" do
      expect(build_template(status: "active").active?).to be true
    end

    it "returns false when status is not active" do
      expect(build_template(status: "draft").active?).to be false
    end
  end

  describe "#in_use_by_non_terminal_send_activity?" do
    it "returns true when a non-terminal campaign references the template" do
      template = create_template
      create(:email_send_activity, :processing, customer: customer, email_template: template)

      expect(template.in_use_by_non_terminal_send_activity?).to be true
    end

    it "returns false when only terminal campaigns reference the template" do
      template = create_template
      create(:email_send_activity, :succeed, customer: customer, email_template: template)

      expect(template.in_use_by_non_terminal_send_activity?).to be false
    end
  end

  describe "content lock while a send is in progress" do
    it "rejects a subject change and keeps the saved subject" do
      template = create_template
      create(:email_send_activity, :processing, customer: customer, email_template: template)

      expect(template.update(subject: "Changed subject")).to be false
      expect(template.errors[:base].join).to include("can't be edited")
      expect(template.reload.subject).not_to eq("Changed subject")
    end

    it "allows a rename" do
      template = create_template
      create(:email_send_activity, :processing, customer: customer, email_template: template)

      expect(template.update(name: "Renamed welcome")).to be true
      expect(template.reload.name).to eq("Renamed welcome")
    end
  end

  describe "#update_status!" do
    it "updates to active while a non-terminal campaign references the template" do
      template = create_template(status: "draft")
      create(:email_send_activity, :pending, customer: customer, email_template: template)

      expect(template.update_status!("active")).to be true
      expect(template.reload.status).to eq("active")
    end

    it "rejects draft while a non-terminal campaign references the template" do
      template = create_template(status: "active")
      create(:email_send_activity, :processing, customer: customer, email_template: template)

      expect(template.update_status!("draft")).to be false
      expect(template.errors[:status]).to include(I18n.t("admin_modules.emails.templates.status.in_use"))
      expect(template.reload.status).to eq("active")
    end

    it "rejects retired while a non-terminal campaign references the template" do
      template = create_template(status: "active")
      create(:email_send_activity, :pending, customer: customer, email_template: template)

      expect(template.update_status!("retired")).to be false
      expect(template.reload.status).to eq("active")
    end

    it "rejects an invalid status without raising" do
      template = create_template

      expect(template.update_status!("unknown")).to be false
      expect(template.errors[:status]).to include(I18n.t("admin_modules.emails.templates.status.invalid"))
      expect(template.reload.status).to eq("active")
    end
  end

  describe "Versionable" do
    it "auto-commits a version when a new template is created" do
      template = create_template(subject: "A")
      expect(template.template_versions.count).to eq(1)
      expect(template.current_version).to be_present
    end

    it "auto-commits a version when subject changes" do
      t = create_template(subject: "A")
      expect {
        t.update!(subject: "B")
      }.to change { t.template_versions.count }.by(1)
    end

    it "auto-commits a version when body_html changes" do
      t = create_template(editor_type: "code", body_html: "<p>A</p>")
      expect {
        t.update!(body_html: "<p>B</p>")
      }.to change { t.template_versions.count }.by(1)
    end

    it "does not commit a version when only status changes" do
      t = create_template(status: "draft")
      expect {
        t.update!(status: "active")
      }.not_to change { t.template_versions.count }
    end

    it "does not commit a version when only name changes" do
      t = create_template(name: "Original")
      expect {
        t.update!(name: "Renamed")
      }.not_to change { t.template_versions.count }
    end

    it "applies the selected default version to scalar columns and ActionText without adding a version" do
      t = create_template(editor_type: "rich_text", subject: "Original", body_text: "R&D <Guest>", body: "<p>Original rich</p>")
      original = t.current_version
      original_fragment = t.body.to_trix_html.to_s
      t.update!(subject: "Changed", body_text: "Changed text", body: "<p>Changed rich</p>")

      expect { t.set_current_version!(original) }.not_to change { t.template_versions.count }

      t.reload
      expect(t.current_version_id).to eq(original.id)
      expect(t.subject).to eq("Original")
      expect(t.body_text).to eq("R&D <Guest>")
      expect(t.body_html).to include("Original rich")
      expect(t.body.to_trix_html.to_s).to eq(original_fragment)
      expect(Emails::TemplateRenderer.render(template: t, vars: {})[:body_html]).to include("Original rich")
    end

    it "applies a code snapshot's editor type and authored HTML when making it default" do
      t = create_template(editor_type: "code", subject: "Code", body_html: "<p>Code body</p>")
      original = t.current_version
      t.update!(editor_type: "rich_text", subject: "Rich", body: "<p>Rich body</p>")

      t.set_current_version!(original)

      expect(t.reload.editor_type).to eq("code")
      expect(t.subject).to eq("Code")
      expect(t.body_html).to eq("<p>Code body</p>")
    end

    %i[set_current_version! restore_as_new!].each do |method|
      it "rolls back #{method} head and scalar changes if ActionText persistence fails" do
        t = create_template(editor_type: "rich_text", subject: "Original", body: "<p>Original rich</p>")
        original = t.current_version
        t.update!(subject: "Changed", body: "<p>Changed rich</p>")
        changed_head = t.current_version_id
        count = t.template_versions.count
        allow(t.rich_text_body).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(t.rich_text_body))

        expect { t.public_send(method, original) }.to raise_error(ActiveRecord::RecordInvalid)

        persisted = described_class.find(t.id)
        expect(persisted.current_version_id).to eq(changed_head)
        expect(persisted.subject).to eq("Changed")
        expect(persisted.body_html).to include("Changed rich")
        expect(persisted.body.to_plain_text).to include("Changed rich")
        expect(persisted.template_versions.count).to eq(count)
      end
    end

    it "rejects default selection from another template's version line" do
      t = create_template
      foreign = create_template.current_version
      expect { t.set_current_version!(foreign) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "applies sparse snapshot defaults without writing NULL into required scalar columns" do
      t = create_template(subject: "Before", body_html: "<p>Before</p>", body_text: "Before text")
      content = t.content_class.store!(customer_id: customer.id, payload: { "subject" => "Sparse subject" })
      sparse = t.commit_version!(content: content)

      expect { t.set_current_version!(sparse) }.not_to change { t.template_versions.count }

      expect(t.reload).to have_attributes(subject: "Sparse subject", body_html: "", body_text: nil,
                                         editor_type: described_class.column_defaults.fetch("editor_type"))
      expect(t.current_version_id).to eq(sparse.id)
    end

    it "normalizes explicitly null snapshot strings and editor type to definition defaults" do
      t = create_template
      content = t.content_class.store!(customer_id: customer.id, payload: {
        "subject" => nil, "body_html" => nil, "body_text" => nil, "editor_type" => nil
      })
      blank = t.commit_version!(content: content)

      t.set_current_version!(blank)

      expect(t.reload).to have_attributes(subject: "", body_html: "", body_text: nil, editor_type: "code")
    end

    it "preserves an authored trix-content class without stripping sibling content on restore" do
      t = create_template(editor_type: "rich_text", body: '<p>Before</p><div class="trix-content"><p>Inside</p></div><p>After</p>')
      original = t.current_version
      original_fragment = t.body.to_trix_html.to_s
      t.update!(body: "<p>Replacement</p>")

      t.restore_as_new!(original)

      expect(t.reload.body.to_trix_html.to_s).to eq(original_fragment)
      expect(t.body_html).to include("Before", "Inside", "After")
    end

    %i[set_current_version! restore_as_new!].each do |method|
      it "preserves the ActionText image identity and metadata during #{method}" do
        blob = Current.set(customer: customer) do
          ActiveStorage::Blob.create_and_upload!(io: StringIO.new("image bytes"), filename: "head-image.png", content_type: "image/png")
        end
        blob.update!(metadata: blob.metadata.merge("width" => 320, "height" => 200))
        attachment = ActionText::Attachment.from_attachable(blob).to_s
        t = create_template(editor_type: "rich_text", subject: "Image snapshot", body: "<p>Image</p>#{attachment}")
        image_version = t.current_version
        original_fragment = t.body.to_trix_html.to_s
        t.update!(body: "<p>Replacement</p>")

        t.public_send(method, image_version)
        t.reload

        expect(t.body.to_trix_html.to_s).to eq(original_fragment)
        expect(t.rich_text_body.embeds.blobs).to include(blob)
        expect(Emails::CompileTemplate.blob_ids_for(t)).to eq([blob.id])
        expect(t.body_html).to include("cid:blob-#{blob.id}", "head-image.png")
        expect(Emails::CompileTemplate.call(t)).to eq(t.body_html)
        raw = Nokogiri::HTML.fragment(t.body.body.to_html).at_css("action-text-attachment")
        expect(raw["content-type"]).to eq("image/png")
        expect(raw["filename"]).to eq("head-image.png")
        expect(raw["width"]).to eq("320")
        expect(raw["height"]).to eq("200")
        preview = Emails::AuthorPreview.call(t, mode: :tokens)
        expect(preview[:body_html]).to include(Rails.application.routes.url_helpers.rails_blob_url(blob, only_path: true))
        expect(preview[:body_html]).not_to include("cid:blob-")
      end
    end

    describe "#restore_as_new!" do
      it "writes the restored version's subject/body_html back onto the template" do
        t = create_template(editor_type: "code", subject: "Original subject", body_html: "<p>Original body</p>")
        original_version = t.current_version

        t.update!(subject: "Changed subject", body_html: "<p>Changed body</p>")
        expect(t.template_versions.count).to eq(2)

        t.restore_as_new!(original_version)
        t.reload

        expect(t.subject).to eq("Original subject")
        expect(t.body_html).to eq("<p>Original body</p>")
        expect(t.template_versions.count).to eq(3)
      end

      it "restores the ActionText body for rich_text templates without corrupting it or double-committing" do
        t = create_template(editor_type: "rich_text", body: "<p>Original rich</p>")
        original_version = t.current_version
        original_fragment = t.body.to_trix_html.to_s

        t.update!(body: "<p>Changed rich</p>")
        expect(t.template_versions.count).to eq(2)

        expect {
          t.restore_as_new!(original_version)
        }.to change { t.template_versions.count }.by(1) # exactly one commit, not two

        t.reload
        expect(t.template_versions.count).to eq(3)

        # Restored fragment is clean — equal to the original, no nested
        # trix-content wrapper or comment annotations from a double-save.
        expect(t.body.to_trix_html.to_s).to eq(original_fragment)
        expect(t.body.to_s).not_to include("trix-content\">\n  <!-- BEGIN")
        expect(t.body_html).to include("Original rich")
        expect(t.body_html).not_to include("trix-content")
      end
    end
  end

  it "preserves authored plain subject/body text while normalizing tokens" do
    t = create_template(subject: "R&D <Guest> #{platform_token('first_name')}", body_text: "1 < 2 & 3 > 0")
    expect(t.reload.subject).to eq("R&D <Guest> #{platform_token('first_name')}")
    expect(t.body_text).to eq("1 < 2 & 3 > 0")
  end
end
