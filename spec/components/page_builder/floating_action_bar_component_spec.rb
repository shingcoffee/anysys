require "rails_helper"

RSpec.describe PageBuilder::FloatingActionBarComponent, type: :component do
  before { render_inline(described_class.new) }

  it "renders selection count placeholder" do
    expect(page).to have_css("[data-page-builder-target='selectionCount']")
  end

  it "renders a width button for each supported width" do
    expect(page).to have_css("button[data-width='full']")
    expect(page).to have_css("button[data-width='two_thirds']")
    expect(page).to have_css("button[data-width='half']")
    expect(page).to have_css("button[data-width='third']")
  end

  it "renders bulk duplicate, delete, move, and group action buttons" do
    expect(page).to have_css("button[data-action*='bulkDuplicate']")
    expect(page).to have_css("button[data-action*='bulkDelete']")
    expect(page).to have_css("button[data-action*='openMoveToPageModal']")
    expect(page).to have_css("button[data-action*='groupIntoSection']")
  end

  it "renders the floating action bar container with correct target" do
    expect(page).to have_css("[data-page-builder-target='floatingActionBar']")
  end

  it "is hidden by default" do
    expect(page).to have_css("[data-page-builder-target='floatingActionBar'].hidden")
  end
end
