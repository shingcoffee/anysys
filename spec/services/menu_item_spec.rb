# frozen_string_literal: true

require "rails_helper"

RSpec.describe MenuItem do
  let(:customer) { double(id: 12345678) }

  describe "#label" do
    it "translates the stable label_key at call time (following the request locale)" do
      item = described_class.new(key: :home, label_key: "chrome.menu_bar.items.home", path_proc: ->(_) { "/" })
      expect(I18n.t("chrome.menu_bar.items.home", locale: :en)).to eq("Home")
      expect(item.label).to eq("Home")
      I18n.with_locale(:"zh-CN") { expect(item.label).to eq(I18n.t("chrome.menu_bar.items.home")) }
    end
  end

  describe "#description" do
    it "translates the description_key at call time" do
      item = described_class.new(key: :email, label_key: "chrome.menu_bar.items.email",
                                 description_key: "chrome.menu_bar.descriptions.email")
      expect(item.description).to eq("Send emails and track delivery")
      I18n.with_locale(:"zh-CN") { expect(item.description).to eq("发送邮件，跟踪投递状态") }
    end

    it "is nil when no description_key is set" do
      expect(described_class.new(key: :home, label_key: "chrome.menu_bar.items.home").description).to be_nil
    end
  end

  describe "#path_for" do
    it "calls the path_proc with the customer" do
      item = described_class.new(key: :home, label_key: "chrome.menu_bar.items.home", path_proc: ->(c) { "/#{c.id}/admin/" })
      expect(item.path_for(customer)).to eq("/12345678/admin/")
    end
  end

  describe "#permitted_for?" do
    it "returns true when permitted_by is nil" do
      item = described_class.new(key: :home, label_key: "chrome.menu_bar.items.home", path_proc: ->(_) { "/" })
      expect(item.permitted_for?(double)).to be true
    end

    it "sends a Symbol predicate to the user" do
      item = described_class.new(key: :m, label_key: "chrome.menu_bar.items.maintenance", path_proc: ->(_) { "/" }, permitted_by: :owner?)
      expect(item.permitted_for?(double(owner?: true))).to be true
      expect(item.permitted_for?(double(owner?: false))).to be false
    end

    it "calls a Proc predicate with the user" do
      item = described_class.new(key: :m, label_key: "chrome.menu_bar.items.maintenance", path_proc: ->(_) { "/" },
                                  permitted_by: ->(u) { u.admin_or_owner? })
      expect(item.permitted_for?(double(admin_or_owner?: true))).to be true
    end

    it "returns false when user does not respond to the Symbol predicate" do
      item = described_class.new(key: :m, label_key: "chrome.menu_bar.items.maintenance", path_proc: ->(_) { "/" }, permitted_by: :mystery?)
      expect(item.permitted_for?(Object.new)).to be false
    end
  end
end
