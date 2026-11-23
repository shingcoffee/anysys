# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageInputsHelper, type: :helper do
  it "is true only for slugs the controller bound" do
    assign(:page_bindings, { "student" => "4" })

    expect(helper.page_input_bound?("student")).to be(true)
    expect(helper.page_input_bound?(:student)).to be(true)
    expect(helper.page_input_bound?("course")).to be(false)
  end

  it "is false when nothing is bound" do
    expect(helper.page_input_bound?("student")).to be(false)
  end
end
