# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::SkipButtonComponent, type: :component do
  it "renders a ghost submit that skips without validating the form" do
    render_inline(described_class.new)

    button = page.find("button[type='submit'][name='_intent'][value='skip']")
    expect(button).to have_text(I18n.t("journeys.runtime.skip"))
    expect(button[:class]).to include("btn-ghost", "min-h-11")
    expect(button[:formnovalidate]).to be_present
  end
end
