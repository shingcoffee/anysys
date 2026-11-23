# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageInfoCardComponent, type: :component do
  subject(:component) { described_class.new(page: page_record, customer_id: 12_345_678) }

  def render_component
    with_request_url("/12345678/admin/maintenance/pages/1", host: "www.example.com") do
      render_inline(component)
    end
  end

  let(:entity) { build_stubbed(:entity, id: 42, name: "Lead") }

  let(:published_page) do
    p = build_stubbed(:page,
                      id: 99,
                      name: "Contact Form",
                      description: "A contact form page",
                      launched: true,
                      public_uuid: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
    allow(p).to receive(:entity).and_return(entity)
    allow(p).to receive(:fields).and_return([{ "id" => "f1" }, { "id" => "f2" }])
    p
  end

  let(:unpublished_page) do
    p = build_stubbed(:page,
                      id: 7,
                      name: "Draft Page",
                      description: nil,
                      launched: false,
                      public_uuid: nil)
    allow(p).to receive(:entity).and_return(nil)
    allow(p).to receive(:fields).and_return([])
    p
  end

  let(:standalone_page) do
    p = build_stubbed(:page,
                      id: 55,
                      name: "Standalone",
                      description: "No entity bound",
                      launched: true,
                      public_uuid: "11111111-2222-4333-8444-555555555555")
    allow(p).to receive(:entity).and_return(nil)
    allow(p).to receive(:fields).and_return([{ "id" => "f1" }])
    p
  end

  describe "#format_datetime" do
    let(:page_record) { unpublished_page }

    it "formats datetime with the locale long time format" do
      datetime = Time.zone.local(2026, 2, 11, 14, 30, 45)
      expect(component.format_datetime(datetime)).to eq(I18n.l(datetime, format: :long))
    end

    it "localizes datetime in zh-CN" do
      datetime = Time.zone.local(2026, 2, 11, 14, 30, 45)
      I18n.with_locale(:"zh-CN") do
        expect(component.format_datetime(datetime)).to eq(I18n.l(datetime, format: :long))
      end
    end

    it "returns dash for blank datetime" do
      expect(component.format_datetime(nil)).to eq("-")
    end
  end

  describe "default rendering (published page with entity)" do
    let(:page_record) { published_page }

    before { render_component }

    it "renders the card wrapper" do
      expect(page).to have_css("div.card")
    end

    it "renders the 'Page Information' heading" do
      expect(page).to have_text("Page Information")
    end

    it "does not render the page ID" do
      expect(page).not_to have_css("dd", text: "99")
    end

    it "renders the page name" do
      expect(page).to have_text("Contact Form")
    end

    it "does not render the slug" do
      expect(page).not_to have_text("Slug")
      expect(page).not_to have_text("contact-form")
    end

    it "renders the fields count" do
      expect(page).to have_text("2 fields")
    end

    it "renders the description" do
      expect(page).to have_text("A contact form page")
    end

    it "renders created and updated labels" do
      expect(page).to have_text("Created")
      expect(page).to have_text("Last Updated")
    end

    it "does not render a public URL row" do
      expect(page).not_to have_text("Public URL")
      expect(page).not_to have_css("a[href*='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee']")
    end
  end

  describe "bound entity — with entity" do
    let(:page_record) { published_page }

    before { render_component }

    it "renders a link to the entity detail page" do
      expect(page).to have_css("a[href*='/entities/']", text: "Lead")
    end

    it "does not show the standalone muted text" do
      expect(page).not_to have_text("standalone page")
    end
  end

  describe "bound entity — standalone page (no entity)" do
    let(:page_record) { standalone_page }

    before { render_component }

    it "shows the standalone muted text" do
      expect(page).to have_text("standalone page")
    end

    it "does not render a link to an entity" do
      expect(page).not_to have_css("a[href*='/entities/']")
    end
  end

  describe "fields count" do
    context "when the page has zero fields" do
      let(:page_record) { unpublished_page }

      before { render_component }

      it "renders '0 fields'" do
        expect(page).to have_text("0 fields")
      end
    end

    context "when the page has one field" do
      let(:page_record) { standalone_page }

      before { render_component }

      it "renders '1 field' (singular)" do
        expect(page).to have_text("1 field")
      end
    end
  end

  describe "description row — blank description" do
    let(:page_record) { unpublished_page }

    before { render_component }

    it "omits the description row when description is absent" do
      expect(page).not_to have_css("dt", text: "Description")
    end
  end

  describe "accessibility" do
    let(:page_record) { published_page }

    before { render_component }

    it "uses dt/dd pairs inside a dl" do
      expect(page).to have_css("dl")
      expect(page).to have_css("dt")
      expect(page).to have_css("dd")
    end

    it "carries no data-controller attribute (no Stimulus needed)" do
      expect(page).not_to have_css("[data-controller]")
    end
  end
end
