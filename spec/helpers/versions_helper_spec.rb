# frozen_string_literal: true

require "rails_helper"

RSpec.describe VersionsHelper, type: :helper do
  describe "#versions_i18n_data" do
    subject(:data) { helper.versions_i18n_data }

    it "returns a flat hash of data-*-value attributes for the versions Stimulus controller" do
      expect(data).to be_a(Hash)
      expect(data.keys).to all(start_with("versions-"))
      expect(data.keys).to all(end_with("-value"))
      expect(data.values).to all(be_a(String))
    end

    it "carries the translated copy (following the request locale)" do
      expect(data[:"versions-item-fallback-label-value"]).to eq(I18n.t("chrome.versions_modal.item_fallback"))
      expect(data[:"versions-delete-button-label-value"]).to eq(I18n.t("common.actions.delete"))

      I18n.with_locale(:"zh-CN") do
        expect(helper.versions_i18n_data[:"versions-item-fallback-label-value"])
          .to eq(I18n.t("chrome.versions_modal.item_fallback"))
      end
    end

    it "merges cleanly into a tag.div data hash without breaking the tag" do
      html = helper.tag.div(data: { controller: "versions" }.merge(data))
      expect(html).to start_with("<div ")
      expect(html).to end_with("</div>")
      # No HTML comment or stray '>' spilled into the attribute list.
      expect(html).not_to include("<!--")
      expect(html).to include('data-versions-item-fallback-label-value=')
    end
  end
end
