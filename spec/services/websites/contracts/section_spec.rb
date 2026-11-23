# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Contracts::Section do
  def validate_with(overrides = {})
    defaults = { "id" => "sec_1", "type" => "rich_text", "props" => { "heading" => "Hello", "body" => "Body" } }
    form = described_class.new(OpenStruct.new(id: nil, type: nil, props: {}))
    form.validate(defaults.merge(overrides.stringify_keys))
    form
  end

  it "accepts a known section type" do
    expect(validate_with).to be_valid
  end

  it "rejects an unknown type" do
    form = validate_with(type: "custom_html")
    expect(form).not_to be_valid
    expect(form.errors[:type]).to include(I18n.t("website.errors.unknown_section"))
  end

  it "rejects a javascript: href" do
    form = validate_with(
      type: "hero_split",
      props: { "headline" => "Hi", "primary_href" => "javascript:alert(1)" }
    )
    expect(form).not_to be_valid
    expect(form.errors[:props]).to include(I18n.t("website.errors.javascript_href"))
  end

  describe "styles" do
    def styled(styles, type: "feature_grid")
      validate_with(type: type, props: { "heading" => "Hi", "headline" => "Hi", "styles" => styles }.slice(*Websites::SectionFields.schema_for(type).map { |f| f[:key] }, "styles"))
    end

    it "accepts tokens, palette and custom hex values on every target kind" do
      expect(styled({
        "section" => { "background" => "#123abc", "heading_font" => "fraunces", "scale" => "lg" },
        "heading" => { "color" => "accent", "size" => "2xl", "weight" => "bold", "italic" => "italic", "align" => "center" },
        "items" => { "background" => "accent_soft", "text" => "ink" },
        "items.title" => { "color" => "#be123c", "font" => "inter" }
      })).to be_valid
      expect(styled({ "buttons" => { "shape" => "square", "fill" => "#0f172a", "text" => "inverse" } }, type: "hero_split")).to be_valid
    end

    [
      { "heading" => { "color" => "url(javascript:alert(1))" } },
      { "heading" => { "color" => "#12345" } },
      { "section" => { "background" => "accent" } },
      { "heading" => { "font" => "comic_sans" } },
      { "heading" => { "size" => "9xl" } },
      { "heading" => { "shape" => "pill" } },
      { "nonexistent" => { "color" => "accent" } },
      { "items.nope" => { "color" => "accent" } }
    ].each do |styles|
      it "rejects #{styles.inspect}" do
        expect(styled(styles)).not_to be_valid
      end
    end

    it "reports invalid styles instead of raising on an unknown type or non-hash shapes" do
      expect(validate_with(type: "bogus", props: { "styles" => { "headline" => { "color" => "accent" } } })).not_to be_valid
      expect(validate_with(type: "bogus", props: { "styles" => "color:red" }).errors[:props]).to be_present
      expect(validate_with(type: "bogus", props: { "styles" => { "section" => "red" } }).errors[:props]).to be_present
    end
  end

  it "rejects a tone outside light/dark" do
    form = validate_with(type: "hero_cinematic", props: { "headline" => "Hi", "tone" => "neon" })
    expect(form).not_to be_valid
    expect(form.errors[:props]).to be_present
  end

  it "accepts a preview request and draft output cards" do
    expect(validate_with(type: "ai_preview", props: {
      "prompt" => "Create a workspace", "items" => [{ "title" => "Records", "body" => "Editable details", "status" => "Draft" }]
    })).to be_valid
  end

  it "validates the optional hero media mode against image and none" do
    [nil, "", "image", "none"].each do |mode|
      expect(validate_with(type: "hero_centered", props: { "media_mode" => mode })).to be_valid
    end
    expect(validate_with(type: "hero_centered", props: { "media_mode" => "video" })).not_to be_valid
  end

  it "rejects an image_side outside left/right" do
    form = validate_with(
      type: "split_image_text",
      props: { "heading" => "Hi", "body" => "Body", "image_side" => "center" }
    )
    expect(form).not_to be_valid
  end

  it "rejects a bento span outside hero/wide/unit" do
    form = validate_with(
      type: "bento_grid",
      props: { "heading" => "Hi", "cells" => [ { "span" => "full", "title" => "X", "body" => "Y" } ] }
    )
    expect(form).not_to be_valid
  end

  it "accepts product tiles with a known size and tone" do
    form = validate_with(
      type: "showcase_tiles",
      props: { "tiles" => [ { "title" => "Aero", "tone" => "dark", "size" => "half" }, { "title" => "Terra", "size" => "" } ] }
    )
    expect(form).to be_valid
  end

  it "rejects a tile size outside full/half" do
    form = validate_with(type: "showcase_tiles", props: { "tiles" => [ { "title" => "Aero", "size" => "third" } ] })
    expect(form).not_to be_valid
    expect(form.errors[:props]).to be_present
  end

  it "rejects a listing aspect outside square/portrait/landscape" do
    form = validate_with(type: "listing_grid", props: { "heading" => "Stays", "aspect" => "panorama", "listings" => [] })
    expect(form).not_to be_valid

    expect(validate_with(type: "listing_grid", props: { "heading" => "Stays", "aspect" => "portrait", "listings" => [] })).to be_valid
  end

  %w[en zh-CN].each do |locale|
    it "reports one localized cardinality error for a valid JSON array exceeding its maximum in #{locale}" do
      I18n.with_locale(locale) do
        form = validate_with(type: "faq", props: { "items" => Array.new(21) { { "question" => "Q", "answer" => "A" } } })
        expected = I18n.t("website.errors.array_count", field: I18n.t("website.admin.pages.form.fields.items"), min: 0, max: 20)

        expect(form.errors[:props]).to eq([expected])
        expect(form.errors[:props]).not_to include(I18n.t("website.errors.invalid_sections"))
      end
    end

    it "reports a localized missing minimum array error in #{locale}" do
      I18n.with_locale(locale) do
        form = validate_with(type: "proof_strip", props: {})
        expect(form.errors[:props]).to eq([
          I18n.t("website.errors.array_count", field: I18n.t("website.admin.pages.form.fields.items"), min: 4, max: 6)
        ])
      end
    end
  end
end
