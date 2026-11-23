# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeveloperDocs::NavigationHelper, type: :helper do
  it "resolves a customer task label at call time when the locale changes" do
    labels = %w[en zh-CN].map do |locale|
      I18n.with_locale(locale) do
        helper.docs_navigation_label("forms", title: "Full form guide title", translation_scope: "customer_docs")
      end
    end
    expect(labels).to eq(["Review forms", "查看表单"])
  end

  %w[en zh-CN].each do |locale|
    it "has a published short label for every customer catalog slug in #{locale}" do
      labels = I18n.t("customer_docs.nav_labels", locale: locale, fallback: false)
      expect(labels.keys.map(&:to_s)).to match_array(CustomerDocs::Catalog.slugs)
      expect(labels.values).to all(be_a(String).and(be_present))
    end

    it "keeps the supplied full title for missing customer labels and other audiences in #{locale}" do
      I18n.with_locale(locale) do
        %w[customer_docs developer_docs other_docs].each do |scope|
          expect(helper.docs_navigation_label("unpublished-guide", title: "Supplied full title", translation_scope: scope)).to eq("Supplied full title")
        end
        expect(helper.docs_navigation_label("forms", title: "Developer form architecture", translation_scope: "developer_docs")).to eq("Developer form architecture")
      end
    end
  end
end
