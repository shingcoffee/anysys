# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageConfigurationHelpers do
  let(:config) do
    {
      "pages" => [
        { "fields" => [
          { "id" => "a", "property_type" => "input" },
          { "id" => "h", "property_type" => "layout", "field_type" => "heading" },
          { "id" => "cols", "field_type" => "columns", "property_type" => "layout", "columns" => [
            { "fields" => [{ "id" => "b" }, { "id" => "d", "property_type" => "layout" }] },
            { "fields" => [{ "field_type" => "columns", "columns" => [{ "fields" => [{ "id" => "c" }] }] }] },
            "junk"
          ] },
          "junk"
        ] },
        "junk",
        { "fields" => [{ "id" => "e" }] }
      ]
    }
  end

  it "flattens columns on every step and drops layout elements" do
    expect(Page.input_fields_in(config).map { |field| field["id"] }).to eq(%w[a b c e])
  end

  it "reads a page's own configuration" do
    page = build(:page)
    page.configuration_json = config

    expect(page.input_fields.map { |field| field["id"] }).to eq(%w[a b c e])
  end

  it "is empty for a missing or malformed configuration" do
    expect(Page.input_fields_in(nil)).to eq([])
    expect(Page.input_fields_in("x")).to eq([])
  end

  describe "#submission_modes" do
    def page_with(form_settings)
      build(:page).tap { |page| page.configuration_json = { "form_settings" => form_settings } }
    end

    it "serves both creates and updates when the page sets no modes" do
      page = page_with({})

      expect(page.submission_modes).to eq(%w[create update])
      expect(page.serves?(:create)).to be(true)
      expect(page.serves?("update")).to be(true)
    end

    it "serves only the configured modes and ignores unknown ones" do
      page = page_with("modes" => %w[update delete])

      expect(page.submission_modes).to eq(%w[update])
      expect(page.serves?(:create)).to be(false)
      expect(page.serves?(:update)).to be(true)
    end

    it "falls back to both modes when none of the configured ones is known" do
      expect(page_with("modes" => "archive").submission_modes).to eq(%w[create update])
    end
  end

  describe "locked inputs and success message" do
    def page_with(form_settings)
      build(:page).tap { |page| page.configuration_json = { "form_settings" => form_settings } }
    end

    it "reads declared inputs as string pairs and drops malformed rows" do
      page = page_with("inputs" => [{ "field" => "student", "entity_id" => 4, "extra" => "x" }, "junk", nil])

      expect(page.page_inputs).to eq([{ "field" => "student", "entity_id" => "4" }])
      expect(page.input_slugs).to eq(%w[student])
      expect(page_with({}).page_inputs).to eq([])
    end

    it "reads a stripped success_message and treats blank as unset" do
      expect(page_with("success_message" => " Welcome, student! ").success_message).to eq("Welcome, student!")
      expect(page_with("success_message" => "   ").success_message).to be_nil
      expect(page_with({}).success_message).to be_nil
    end
  end
end
