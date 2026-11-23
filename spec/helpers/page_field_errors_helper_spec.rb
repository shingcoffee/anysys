# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageFieldErrorsHelper, type: :helper do
  it "reads a field's errors by slug" do
    assign(:page_field_errors, { "name" => ["can't be blank"] })

    expect(helper.page_field_errors(:name)).to eq(["can't be blank"])
    expect(helper.page_field_errors("email")).to eq([])
    expect(helper.page_field_error("name")).to include("can&#39;t be blank", "data-field-error")
    expect(helper.page_field_error("email")).to be_blank
  end

  it "has no errors when the page wasn't refused" do
    expect(helper.page_field_errors("name")).to eq([])
  end
end
