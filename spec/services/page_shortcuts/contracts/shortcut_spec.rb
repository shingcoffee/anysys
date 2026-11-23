# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageShortcuts::Contracts::Shortcut do
  let_it_be(:customer) { create(:customer) }
  let(:page) { create(:page, customer: customer, launched: true, audience_member: true, audience_public: true) }
  let(:shortcut) { PageShortcut.new(customer_id: customer.id) }

  def validate(path: "/join", target_type: "Page", target_id: page.id)
    form = described_class.new(shortcut)
    form.validate("path" => path, "target_type" => target_type, "target_id" => target_id)
    form
  end

  it "normalizes valid paths and allows explicit root mappings" do
    form = validate(path: "campaign/spring/")
    expect(form).to be_valid
    expect(form.path).to eq("/campaign/spring")
    expect(validate(path: "/")).to be_valid
  end

  it "reports path, target and reserved namespace errors by field" do
    expect(validate(path: "https://example.com").errors[:path]).to include(I18n.t("page_shortcuts.errors.invalid_path"))
    expect(validate(path: "/admin/users").errors[:path]).to include(I18n.t("page_shortcuts.errors.reserved_path"))
    expect(validate(target_type: "Customer").errors[:target]).to include(I18n.t("page_shortcuts.errors.unavailable_target"))
  end

  it "rejects duplicates but permits updating the same row" do
    record = PageShortcut.create!(customer_id: customer.id, path: "/join", target: page)
    expect(validate.errors[:path]).to include(I18n.t("page_shortcuts.errors.path_taken"))
    form = described_class.new(record)
    expect(form.validate("path" => "/join")).to be(true)
  end

  it "returns equivalent localized errors with locale key parity" do
    en = I18n.t("page_shortcuts.errors", locale: :en)
    zh = I18n.t("page_shortcuts.errors", locale: :"zh-CN")
    expect(zh.keys).to match_array(en.keys)
    I18n.with_locale(:"zh-CN") do
      expect(validate(path: "/admin").errors[:path]).to include(zh.fetch(:reserved_path))
    end
  end
end
