# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::PublicComponent, type: :component do
  let(:component) { described_class.new }
  let(:request_params) { {} }

  before do
    allow(component).to receive(:customer_id).and_return(12345678)
    view_helpers = double(params: request_params, request: double(host: "www.example.com"))
    allow(view_helpers).to receive(:page_shortcuts_mounted_path) { |path| path }
    allow(component).to receive(:helpers).and_return(view_helpers)
  end

  it "keeps default-English slugs and root URLs byte-identical without an explicit locale" do
    I18n.with_locale(:en) do
      expect(component.href_for("about")).to eq("/12345678/about")
      expect(component.href_for("/auth/sign_up")).to eq("/auth/sign_up")
      expect(component.href_for("/auth/sign_up?next=%2Fworkspace#start")).to eq("/auth/sign_up?next=%2Fworkspace#start")
    end
  end

  it "carries Chinese through slugs and root paths while retaining query values and fragments" do
    I18n.with_locale(:"zh-CN") do
      expect(component.href_for("about")).to eq("/12345678/about?locale=zh-CN")
      expect(component.href_for("/auth/sign_up")).to eq("/auth/sign_up?locale=zh-CN")
      uri = Addressable::URI.parse(component.href_for("/auth/sign_up?tag=one&tag=two&next=%2Fworkspace&locale=en#start"))
      expect(uri.path).to eq("/auth/sign_up")
      expect(uri.fragment).to eq("start")
      expect(uri.query_values(Array)).to contain_exactly(["tag", "one"], ["tag", "two"], ["next", "/workspace"], ["locale", "zh-CN"])
    end
  end

  it "never changes external HTTPS URLs, including media URLs and their own locale" do
    I18n.with_locale(:"zh-CN") do
      %w[https://example.com/docs https://cdn.example.com/photo.jpg?locale=en#image].each do |href|
        expect(component.href_for(href)).to eq(href)
      end
      expect(component.href_for("javascript:alert(1)")).to be_nil
      expect(component.href_for("//example.com")).to be_nil
      expect(component.href_for(nil)).to be_nil
    end
  end

  context "with an explicit English switch" do
    let(:request_params) { { locale: "en" } }

    it "carries English so a saved Chinese cookie cannot undo the switch" do
      I18n.with_locale(:en) do
        expect(component.href_for("about")).to eq("/12345678/about?locale=en")
        expect(component.href_for("/auth/sign_up?locale=zh-CN#start")).to eq("/auth/sign_up?locale=en#start")
      end
    end
  end

  context "with an invalid explicit locale" do
    let(:request_params) { { locale: "unknown" } }

    it "retains ordinary default URLs" do
      I18n.with_locale(:en) { expect(component.href_for("/auth/sign_up")).to eq("/auth/sign_up") }
    end
  end
end
