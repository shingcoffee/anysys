# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Contracts::Page do
  let_it_be(:customer) { create(:customer) }
  let(:website) { build(:website, customer: customer) }
  let(:page) { build(:website_page, website: website, customer: customer) }

  def validate_with(overrides = {})
    defaults = {
      "title" => "About",
      "slug" => "about",
      "published" => false,
      "nav_visible" => true,
      "home" => false,
      "sections" => []
    }
    form = described_class.new(page)
    form.validate(defaults.merge(overrides.stringify_keys))
    form
  end

  it "is valid with a title and slug" do
    expect(validate_with).to be_valid
  end

  it "accepts a blank or registered theme_key and rejects anything else" do
    expect(validate_with(theme_key: "")).to be_valid
    expect(validate_with(theme_key: "midnight")).to be_valid
    expect(validate_with(theme_key: "layout").errors[:theme_key]).to be_present
    expect(validate_with(theme_key: "neon").errors[:theme_key]).to be_present
  end

  it "requires a title" do
    form = validate_with(title: "")
    expect(form).not_to be_valid
    expect(form.errors[:title]).to be_present
  end

  it "allows a blank slug on the home page" do
    expect(validate_with(home: true, slug: "")).to be_valid
  end

  it "rejects a reserved slug" do
    form = validate_with(slug: "preview")
    expect(form).not_to be_valid
    expect(form.errors[:slug]).to include(I18n.t("website.errors.reserved_slug"))
  end

  it "rejects a slug already used on the site" do
    website.save!
    create(:website_page, website: website, customer: customer, title: "About", slug: "about")
    other = build(:website_page, website: website, customer: customer, title: "About copy", slug: "about")
    form = described_class.new(other)
    form.validate(
      "title" => "About copy",
      "slug" => "about",
      "published" => false,
      "nav_visible" => true,
      "home" => false,
      "sections" => []
    )

    expect(form).not_to be_valid
    expect(form.errors[:slug].join).to include(I18n.t("website.errors.slug_taken"))
  end

  it "rejects an unknown section type" do
    form = validate_with(sections: [ { "type" => "html_dump", "props" => {} } ])
    expect(form).not_to be_valid
    expect(form.errors[:sections].join).to include(I18n.t("website.errors.unknown_section"))
  end

  it "rejects a javascript: href on a section" do
    form = validate_with(
      sections: [
        {
          "type" => "cta_band",
          "props" => {
            "headline" => "Go",
            "button_label" => "Go",
            "button_href" => "javascript:alert(1)"
          }
        }
      ]
    )
    expect(form).not_to be_valid
    expect(form.errors[:sections].join).to include(I18n.t("website.errors.javascript_href"))
  end

  context "page shortcut collisions" do
    let(:target) { create(:page, :for_member, :for_public, customer: customer, launched: true) }

    it "rejects a slug taking another target's alias on creation and publication" do
      PageShortcut.create!(customer_id: customer.id, path: "/about", target: target)
      expect(validate_with.errors[:slug]).to include(I18n.t("page_shortcuts.errors.shortcut_slug_taken"))
      expect(validate_with(published: true).errors[:slug]).to include(I18n.t("page_shortcuts.errors.shortcut_slug_taken"))
    end

    it "permits the same website-page target and ignores other tenants' aliases" do
      website.save!
      page.save!
      PageShortcut.create!(customer_id: customer.id, path: "/about", target: page)
      expect(validate_with).to be_valid
      other = create(:customer)
      PageShortcut.create!(customer_id: other.id, path: "/story", target: target)
      expect(validate_with(slug: "story")).to be_valid
    end

    it "allows root overrides independently of setting a website page as home" do
      PageShortcut.create!(customer_id: customer.id, path: "/", target: target)
      expect(validate_with(home: true, slug: "")).to be_valid
    end
  end
end
