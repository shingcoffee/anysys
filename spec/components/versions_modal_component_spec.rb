# frozen_string_literal: true

require "rails_helper"

RSpec.describe VersionsModalComponent, type: :component do
  before { render_inline(described_class.new) }

  it "renders the modal shell with list, content, diff and error targets" do
    expect(page).to have_css("[data-versions-target='modal']", visible: :all)
    expect(page).to have_css("[data-versions-target='title']", visible: :all)
    expect(page).to have_css("[data-versions-target='list']", visible: :all)
    expect(page).to have_css("[data-versions-target='content']", visible: :all)
    expect(page).to have_css("[data-versions-target='diffButton']", visible: :all)
    expect(page).to have_css("[data-versions-target='error']", visible: :all)
  end

  it "renders the selection-aware targets" do
    %w[listView count hint selectionInfo clearButton errorMessage].each do |target|
      expect(page).to have_css("[data-versions-target='#{target}']", visible: :all)
    end
  end

  it "renders the pagination controls for the version list" do
    %w[pagination pageInfo prevButton nextButton].each do |target|
      expect(page).to have_css("[data-versions-target='#{target}']", visible: :all)
    end
  end

  it "renders the version list as a table with the expected column headers" do
    expect(page).to have_css("table thead th", text: "Version", visible: :all)
    expect(page).to have_css("table thead th", text: "Based on", visible: :all)
    expect(page).to have_css("table thead th", text: "Status", visible: :all)
    expect(page).to have_css("table thead th", text: "Description", visible: :all)
    expect(page).to have_css("table thead th", text: "Created", visible: :all)
    expect(page).to have_css("table thead th", text: "Actions", visible: :all)
    # the version rows are rendered into the table body via Stimulus
    expect(page).to have_css("tbody[data-versions-target='list']", visible: :all)
  end

  it "is a dialog whose primary action compares the selected versions" do
    expect(page).to have_css("[role='dialog'][aria-modal='true']", visible: :all)
    expect(page).to have_css(
      "[data-versions-target='diffButton'][data-action~='click->versions#diff']",
      text: "Compare selected", visible: :all
    )
  end

  it "does not render a newButton target" do
    expect(page).not_to have_css("[data-versions-target='newButton']", visible: :all)
  end

  it "labels the dialog with the generic versions-title id" do
    expect(page).to have_css("[aria-labelledby='versions-title']", visible: :all)
    expect(page).to have_css("#versions-title", text: "Version history", visible: :all)
  end

  it "wires close buttons to the versions controller" do
    expect(page).to have_css("[data-action='click->versions#close']", visible: :all)
  end
end
