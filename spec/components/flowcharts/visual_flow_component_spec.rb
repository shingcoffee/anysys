# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flowcharts::VisualFlowComponent, type: :component do
  let(:flowchart) { create(:flowchart, :simple) }

  def render_component
    render_inline(described_class.new(flowchart: flowchart))
  end

  context "with a compiled activity" do
    before { render_component }

    it "mounts the mermaid controller with both diagram sources" do
      mount = page.find("[data-controller='mermaid']")
      graph = ActivityDiagramGenerator.new(flowchart).graph
      expect(mount["data-mermaid-source-value"]).to eq(graph.to_mermaid)
      expect(mount["data-mermaid-alternate-value"]).to eq(graph.to_mermaid(failure_paths: true))
      expect(mount["data-mermaid-render-error-format-value"]).to eq("Error rendering diagram: {error}")
      expect(page).to have_css("[data-mermaid-target='diagram']")
    end

    it "offers a failure-paths switch wired to the controller" do
      switch = page.find("input[role='switch']", visible: :all)
      expect(switch["data-action"]).to eq("change->mermaid#switch")
      expect(page).to have_text("Show failure paths")
    end

    it "shows a legend of the shapes in the diagram" do
      expect(page).to have_text("Legend")
      expect(page).to have_text("Start")
      expect(page).to have_text("Process")
      expect(page).to have_text("End")
      expect(page).not_to have_text("Decision")
    end
  end

  context "with a label that would break out of the attribute" do
    before do
      flowchart.update!(configuration: flowchart.configuration.sub('"label":"Process"', '"label":"\\"><script>alert(1)</script>"'))
      flowchart.update_column(:activity, ActivityGenerator.new(flowchart.reload).generate)
      render_component
    end

    it "keeps the Mermaid source inside the attribute" do
      expect(page).not_to have_css("script")
      expect(page.find("[data-controller='mermaid']")["data-mermaid-source-value"]).to include("#quot;#gt;#lt;script#gt;")
    end
  end

  context "without an activity" do
    before do
      flowchart.update_column(:activity, nil)
      render_component
    end

    it "shows the empty state without a switch or diagram source" do
      expect(page).to have_text("No visual flow generated yet")
      expect(page).to have_text("Add elements to generate visual flow")
      expect(page).not_to have_css("input[role='switch']", visible: :all)
      expect(page.find("[data-controller='mermaid']")["data-mermaid-source-value"]).to be_nil
    end
  end

  context "in Chinese" do
    around { |example| I18n.with_locale(:"zh-CN") { example.run } }

    before { render_component }

    it "translates the card chrome" do
      expect(page).to have_text("可视化流程")
      expect(page).to have_text("显示失败路径")
      expect(page).to have_text("图例")
    end
  end
end
