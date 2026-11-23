# frozen_string_literal: true

require "rails_helper"

RSpec.describe PagePrefillHelper, type: :helper do
  it "returns the value for a known slug" do
    helper.instance_variable_set(:@page_prefill, { "course" => "12" })

    expect(helper.page_prefill_value("course")).to eq("12")
    expect(helper.page_prefill_value(:course)).to eq("12")
  end

  it "returns nil when the slug is missing or prefill is unset" do
    expect(helper.page_prefill_value("course")).to be_nil

    helper.instance_variable_set(:@page_prefill, { "course" => "12" })
    expect(helper.page_prefill_value("missing")).to be_nil
  end

  it "falls back to the default only for a missing slug, keeping a prefilled blank" do
    helper.instance_variable_set(:@page_prefill, { "course" => "", "room" => nil })

    expect(helper.page_prefill_value("course", default: "Math")).to eq("")
    expect(helper.page_prefill_value("room", default: "A1")).to be_nil
    expect(helper.page_prefill_value("missing", default: "Math")).to eq("Math")
  end
end
