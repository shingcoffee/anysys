# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageBuilder::FieldTypeSettingsComponent, type: :component do
  before { render_inline(described_class.new) }

  it "renders the typeSettingsSection target wrapper" do
    expect(page).to have_css("[data-page-builder-target='typeSettingsSection']")
  end

  it "renders data-type-setting containers for every field category" do
    %w[
      fieldMaxLength fieldMinLength fieldPattern fieldAutocomplete
      fieldRows fieldResize
      fieldShowToggle
      fieldAllowBlank fieldSearchable fieldInlineLayout fieldMinMaxSelections
      fieldOnOffLabel
      fieldMinMaxValue fieldStep fieldShowValue
      fieldCurrencySymbol fieldDecimalPlaces
      fieldMaxRating fieldAllowHalf
      fieldMinMaxConstraint fieldTimeStep
      fieldAllowMultiple fieldPhonePattern
      fieldToolbar
      fieldCanvasHeight fieldPenColor fieldPenWidth
      fieldAcceptTypes fieldMaxFileSize
      fieldColorFormat
    ].each do |key|
      expect(page).to have_css("[data-type-setting='#{key}']"),
        "expected data-type-setting=#{key} to be present"
    end
  end

  it "wires inputs to the page-builder Stimulus controller" do
    expect(page).to have_css(
      "input[data-page-builder-target='fieldMaxLength'][data-action='input->page-builder#updateFieldProperty']"
    )
    expect(page).to have_css(
      "select[data-page-builder-target='fieldCurrencySymbol'][data-action='change->page-builder#updateFieldProperty']"
    )
    expect(page).to have_css(
      "select[data-page-builder-target='fieldMaxRating'][data-action='change->page-builder#updateFieldProperty']"
    )
  end

  it "renders the Currency section with expected options" do
    expect(page).to have_css("select[data-page-builder-target='fieldCurrencySymbol']")
    expect(page).to have_css("option", text: "$ (USD)")
    expect(page).to have_css("option", text: "€ (EUR)")
  end

  it "renders the Rating section with max-rating options" do
    expect(page).to have_css("select[data-page-builder-target='fieldMaxRating']")
    expect(page).to have_css("option[value='5'][selected]")
  end

  it "renders the Color section with color-format options" do
    expect(page).to have_css("select[data-page-builder-target='fieldColorFormat']")
    expect(page).to have_css("option[value='hex'][selected]", text: "Hex (#rrggbb)")
    expect(page).to have_css("option[value='rgb']", text: "RGB")
    expect(page).to have_css("option[value='hsl']", text: "HSL")
  end

  it "renders the Rich Text toolbar checkboxes" do
    expect(page).to have_css("[data-page-builder-target='fieldToolbar']")
    %w[toolbar_bold toolbar_italic toolbar_underline toolbar_link toolbar_list
       toolbar_image toolbar_heading].each do |prop|
      expect(page).to have_css(
        "input[type='checkbox'][data-property='#{prop}'][data-action='change->page-builder#updateFieldProperty']"
      )
    end
  end
end
