# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartDefinitions::ActionLabel do
  it "prefers flowchart_elements.template_labels when the key exists" do
    I18n.with_locale(:en) do
      expect(described_class.for("save_model")).to eq(I18n.t("flowchart_elements.template_labels.save_model"))
      expect(described_class.for("start")).to eq(I18n.t("flowchart_elements.template_labels.start"))
    end
    I18n.with_locale(:"zh-CN") do
      expect(described_class.for("save_model")).to eq("保存记录")
      expect(described_class.for("start")).to eq("开始")
    end
  end

  it "uses the editor action label when no template_labels key exists" do
    I18n.with_locale(:en) do
      expect(described_class.for("collection_manipulate")).to eq(I18n.t("flowchart_actions.collection_manipulate.label"))
      expect(described_class.for("query_models")).to eq(I18n.t("flowchart_actions.query_models.label"))
    end
    I18n.with_locale(:"zh-CN") do
      expect(described_class.for("collection_manipulate")).to eq(I18n.t("flowchart_actions.collection_manipulate.label"))
      expect(described_class.for("query_models")).to eq(I18n.t("flowchart_actions.query_models.label"))
    end
  end

  it "falls back to the catalog English label when no translation exists" do
    expect(described_class.for("b")).to eq(FlowchartDefinitions::Palette.human_label("b"))
  end
end
