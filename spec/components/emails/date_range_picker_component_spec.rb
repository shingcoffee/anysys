# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::DateRangePickerComponent, type: :component do
  it "renders date inputs and an apply button" do
    render_inline(described_class.new(url: "/test", since: Date.new(2023, 10, 1), until_date: Date.new(2023, 10, 15)))

    expect(page).to have_field("since")
    expect(page).to have_field("until")
    expect(page).to have_button(I18n.t("admin_modules.emails.analytics.date_range.apply"))
  end

  it "uses default labels when not provided" do
    render_inline(described_class.new(url: "/test"))
    expect(page).to have_field("since")
    expect(page).to have_field("until")
  end
end
