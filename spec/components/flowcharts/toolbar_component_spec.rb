# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flowcharts::ToolbarComponent, type: :component do
  let(:flowchart) { create(:flowchart) }

  describe "rendering with a non-launched flowchart" do
    before { render_inline(described_class.new(flowchart: flowchart)) }

    it "renders the toolbar Stimulus controller wrapper" do
      expect(page).to have_css("[data-controller='toolbar']")
    end

    it "leaves the toolbar writable for a draft flowchart" do
      expect(page).not_to have_css("[data-toolbar-read-only-value='true']")
    end

    it "renders the flowchart name as a link" do
      expect(page).to have_link(flowchart.name)
    end

    it "renders the zoom-out button wired to the toolbar controller" do
      expect(page).to have_css("button[data-action='click->toolbar#zoomOut']")
    end

    it "renders the zoom-in button wired to the toolbar controller" do
      expect(page).to have_css("button[data-action='click->toolbar#zoomIn']")
    end

    it "renders the fit-to-content button wired to the toolbar controller" do
      expect(page).to have_css("button[data-action='click->toolbar#fitToContent']")
    end

    it "renders the zoom level target span" do
      expect(page).to have_css("[data-toolbar-target='zoomLevel']", text: "100%")
    end

    it "renders the save button wired to the toolbar controller" do
      expect(page).to have_css("button[data-action='click->toolbar#save']")
    end

    it "renders the undo button with the correct target" do
      expect(page).to have_css("button[data-action='click->toolbar#undo'][data-toolbar-target='undoButton']")
    end

    it "renders the redo button with the correct target" do
      expect(page).to have_css("button[data-action='click->toolbar#redo'][data-toolbar-target='redoButton']")
    end

    it "renders the validate button wired to flowchart-canvas" do
      expect(page).to have_css("button[data-action='click->flowchart-canvas#validate']")
    end

    it "renders the overflow menu toggle button" do
      expect(page).to have_css("button[data-action='click->toolbar#toggleOverflow']")
    end

    it "renders the overflow menu target" do
      expect(page).to have_css("[data-toolbar-target='overflowMenu']")
    end

    it "renders the tidy-layout overflow item" do
      expect(page).to have_css("button[data-action*='toolbar#autoLayout']", text: "Tidy layout")
    end

    it "renders the clear canvas overflow item" do
      expect(page).to have_css("button[data-action*='toolbar#clear']", text: "Clear Canvas")
    end

    it "renders the save dot indicator target" do
      expect(page).to have_css("[data-toolbar-target='saveDot']")
    end

    it "renders the validation badge target" do
      expect(page).to have_css("[data-flowchart-canvas-target='validationBadge']")
    end

    it "passes the save toasts to the toolbar controller" do
      toolbar = page.find("[data-controller='toolbar']")
      expect(toolbar["data-toolbar-read-only-save-message-value"]).to eq("Cannot save a launched flowchart. Take it offline first.")
      expect(toolbar["data-toolbar-saved-message-value"]).to eq("Flowchart saved successfully")
      expect(toolbar["data-toolbar-save-failed-message-value"]).to eq("Failed to save flowchart")
      expect(toolbar["data-toolbar-error-separator-value"]).to eq(", ")
      expect(toolbar["data-toolbar-edge-insert-button-label-value"]).to eq("Insert an element")
      expect(toolbar["data-toolbar-edge-insert-menu-label-value"]).to eq("Choose an element to insert")
    end
  end

  describe "rendering in zh-CN" do
    around { |example| I18n.with_locale(:"zh-CN") { example.run } }

    before { render_inline(described_class.new(flowchart: flowchart)) }

    it "passes the translated save toasts" do
      toolbar = page.find("[data-controller='toolbar']")
      expect(toolbar["data-toolbar-read-only-save-message-value"]).to eq("已上线的流程图无法保存，请先下线。")
      expect(toolbar["data-toolbar-saved-message-value"]).to eq("流程图保存成功")
      expect(toolbar["data-toolbar-save-failed-message-value"]).to eq("流程图保存失败")
      expect(toolbar["data-toolbar-error-separator-value"]).to eq("，")
      expect(toolbar["data-toolbar-edge-insert-button-label-value"]).to eq("插入元素")
      expect(toolbar["data-toolbar-edge-insert-menu-label-value"]).to eq("选择要插入的元素")
    end
  end

  describe "rendering with a launched flowchart" do
    let(:flowchart) { create(:flowchart, :launched_status) }

    before { render_inline(described_class.new(flowchart: flowchart)) }

    it "keeps save enabled, since saving stages a draft version" do
      expect(page).not_to have_css("[data-toolbar-read-only-value='true']")
      expect(page).to have_css("button[data-toolbar-target='saveButton']:not([aria-disabled])")
    end
  end
end
