require "rails_helper"

RSpec.describe Admin::Settings::MemberVisibilityChoiceComponent, type: :component do
  it "keeps required content submitted while preventing deselection" do
    render_inline(described_class.new(name: "columns[]", choice: { key: :amount, label: "Amount", locked: true, checked: true }))
    expect(page).to have_css("input[type='checkbox'][disabled][checked]")
    expect(page).to have_css("input[type='hidden'][name='columns[]'][value='amount']", visible: :all)
    expect(page).to have_text("always shown")
  end

  it "allows optional content to be deselected" do
    render_inline(described_class.new(name: "columns[]", choice: { key: :date, label: "Date", locked: false, checked: false }))
    expect(page).to have_unchecked_field("Date", disabled: false)
    expect(page).not_to have_css("input[type='hidden']", visible: :all)
  end
end
