# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Assistant::Undo do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }
  let!(:website) { create(:website, customer: customer) }
  let!(:home) { create(:website_page, :home, website: website, customer: customer, position: 0) }

  def statement(headline)
    { "id" => "sec_#{headline.parameterize}", "type" => "statement", "props" => { "headline" => headline } }
  end

  def save(page, **params)
    result = Websites::Activities::SavePage.call(page: page, params: params, structure_editable: true)
    expect(result.success?).to be(true), Array(result.errors).join
    result.model
  end

  # Mirrors Processor: snapshot before the save, entry from the saved page.
  def revise(page, **params)
    before = described_class.snapshot(page)
    described_class.entry(save(page, **params), before: before)
  end

  def build_page(title, slug)
    page = WebsitePage.new(website: website, customer_id: customer.id, published: false, position: 5)
    described_class.entry(save(page, title: title, slug: slug, sections: [ statement("New #{title}") ]))
  end

  def reply_with(*entries)
    create(:ai_assistant_message, :assistant, conversation: conversation, customer: customer,
      metadata: { "changes" => [], described_class::KEY => { "pages" => entries } })
  end

  def undo(message) = described_class.call(message: message, customer: customer)

  def t(key, **options) = I18n.t("ai_assistant.assistant.website.undo.#{key}", **options)

  let!(:about) do
    create(:website_page, website: website, customer: customer, title: "About", slug: "about", position: 1,
      sections: [ statement("Our story") ])
  end

  it "deletes the pages the reply created and puts back the pages it revised" do
    message = reply_with(
      revise(about, title: "About us", slug: "about-us", nav_visible: false, sections: [ statement("Rewritten") ]),
      build_page("Menu", "menu")
    )

    result = undo(message)

    expect(result.success?).to be(true)
    expect(website.pages.find_by(slug: "menu")).to be_nil
    expect(about.reload).to have_attributes(title: "About", slug: "about", nav_visible: true)
    expect(about.sections.map { |section| section.dig("props", "headline") }).to eq([ "Our story" ])
    expect(described_class.state(message.reload)).to eq(:undone)
  end

  it "keeps the home page's slug when it puts the home page back" do
    message = reply_with(revise(home, title: "Welcome back", sections: [ statement("Fresh") ]))

    expect(undo(message).success?).to be(true)
    expect(home.reload).to have_attributes(home: true, slug: "")
  end

  describe "a home page the reply created for an empty site" do
    let(:message) do
      website.pages.delete_all
      page = WebsitePage.new(website: website, customer_id: customer.id, published: false, position: 0)
      reply_with(described_class.entry(save(page, title: "Home", home: true, sections: [ statement("Hi") ])), build_page("Menu", "menu"))
    end

    it "is deleted along with the reply's other pages" do
      expect(undo(message).success?).to be(true)
      expect(website.pages.reload).to be_empty
    end

    it "is kept while a page added since relies on it" do
      message
      create(:website_page, website: website, customer: customer, title: "Contact", slug: "contact", position: 3)

      expect(undo(message).errors).to eq([ t("errors.home_in_use", title: "Home") ])
      expect(website.pages.where(home: true).pluck(:title)).to eq([ "Home" ])
      expect(website.pages.find_by(slug: "menu")).to be_present
    end
  end

  describe "refusals, which leave every page as it is" do
    let(:message) do
      reply_with(revise(about, title: "About us", sections: [ statement("Rewritten") ]), build_page("Menu", "menu"))
    end

    def expect_untouched
      expect(website.pages.find_by(slug: "menu")).to be_present
      expect(described_class.state(message.reload)).to eq(:available)
    end

    it "refuses when a page was edited after the reply" do
      message
      save(about.reload, title: "About the team")

      result = undo(message)

      expect(result.success?).to be(false)
      expect(result.errors).to eq([ t("errors.changed", title: "About the team") ])
      expect(about.reload.title).to eq("About the team")
      expect_untouched
    end

    it "refuses when a page was published after the reply" do
      message
      about.update!(published: true)

      expect(undo(message).errors).to eq([ t("errors.published", title: "About us") ])
      expect_untouched
    end

    it "refuses when a page was deleted after the reply" do
      message
      about.destroy!

      expect(undo(message).errors).to eq([ t("errors.missing", title: "About") ])
      expect(website.pages.find_by(slug: "menu")).to be_present
    end

    it "rolls back the deletions when a revised page cannot be put back" do
      message = reply_with(revise(about, slug: "about-us", sections: [ statement("Rewritten") ]), build_page("Menu", "menu"))
      create(:website_page, website: website, customer: customer, title: "About (new)", slug: "about", position: 7)
      deleted = []
      allow_any_instance_of(WebsitePage).to receive(:destroy!).and_wrap_original do |original|
        deleted << original.receiver.slug
        original.call
      end

      result = undo(message)

      expect(deleted).to eq([ "menu" ])
      expect(result.success?).to be(false)
      expect(result.errors).to contain_exactly(a_string_starting_with(t("errors.restore_failed", title: "About", details: "")))
      expect(website.pages.find_by(slug: "menu")).to be_present
      expect(about.reload.slug).to eq("about-us")
    end

    it "asks for a retry when the database is busy or a slug was taken meanwhile" do
      message
      [ ActiveRecord::StatementTimeout, ActiveRecord::RecordNotUnique ].each do |error|
        allow(Websites::Activities::SavePage).to receive(:call).and_raise(error)

        expect(undo(message).errors).to eq([ t("errors.retry") ])
        expect(about.reload.title).to eq("About us")
        expect_untouched
      end
    end

    it "does nothing a second time" do
      undo(message)

      expect(undo(message).errors).to eq([ t("errors.unavailable") ])
    end

    it "reloads Undo availability under the boundary instead of trusting a stale reply" do
      stale = AiAssistant::Message.find(message.id)
      expect(described_class.state(stale)).to eq(:available)
      expect(undo(message)).to be_success
      save(about.reload, title: "Human edit after Undo", sections: [statement("Keep this edit")])
      before = about.reload.attributes.deep_dup

      expect(undo(stale).errors).to eq([t("errors.unavailable")])
      expect(about.reload.attributes).to eq(before)
    end

    it "rechecks the persisted Undo marker when it changes before boundary acquisition" do
      message
      before = about.reload.attributes.deep_dup
      updated = false
      allow(PageShortcuts::Collisions).to receive(:with_customer_lock).and_wrap_original do |original, **args, &operation|
        unless updated
          reply = AiAssistant::Message.find(message.id)
          metadata = reply.metadata_json.deep_dup
          metadata[described_class::KEY]["undone_at"] = Time.current.iso8601
          reply.update!(metadata: metadata)
          updated = true
        end
        original.call(**args, &operation)
      end

      expect(undo(message).errors).to eq([t("errors.unavailable")])
      expect(about.reload.attributes).to eq(before)
      expect(website.pages.find_by(slug: "menu")).to be_present
      expect(described_class.state(message.reload)).to eq(:undone)
    end

    it "refuses publication at the customer boundary before reverting any page" do
      message
      published_state = nil
      allow(PageShortcuts::Collisions).to receive(:with_customer_lock).and_wrap_original do |original, **args, &operation|
        unless published_state
          about.reload.update!(published: true)
          published_state = about.reload.attributes.deep_dup
        end
        original.call(**args, &operation)
      end

      result = undo(message)
      expect(result.errors).to eq([t("errors.published", title: "About us")])
      expect(about.reload.attributes).to eq(published_state)
      expect_untouched
    end

    it "refuses a changed fingerprint at the customer boundary before reverting any page" do
      message
      edited_state = nil
      allow(PageShortcuts::Collisions).to receive(:with_customer_lock).and_wrap_original do |original, **args, &operation|
        unless edited_state
          about.reload.update!(title: "Human revision", sections: [statement("Latest human content")])
          edited_state = about.reload.attributes.deep_dup
        end
        original.call(**args, &operation)
      end

      result = undo(message)
      expect(result.errors).to eq([t("errors.changed", title: "Human revision")])
      expect(about.reload.attributes).to eq(edited_state)
      expect_untouched
    end
  end

  it "never reaches another tenant's page named in an entry" do
    other_site = create(:website, customer: other_customer)
    theirs = create(:website_page, website: other_site, customer: other_customer, title: "Theirs", slug: "theirs", position: 1)
    entry = described_class.entry(theirs).merge("title" => "Theirs")
    message = reply_with(entry)

    expect(undo(message).errors).to eq([ t("errors.missing", title: "Theirs") ])
    expect(theirs.reload).to be_persisted
  end

  it "has no state for a reply that wrote nothing to the website" do
    message = create(:ai_assistant_message, :assistant, conversation: conversation, customer: customer, metadata: { "changes" => [] })

    expect(described_class.state(message)).to be_nil
    expect(undo(message).errors).to eq([ t("errors.unavailable") ])
  end
end
