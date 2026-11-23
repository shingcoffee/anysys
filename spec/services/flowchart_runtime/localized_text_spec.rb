# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::LocalizedText do
  it "returns the request-locale string and falls back to English" do
    value = { "en" => "Thank you.", "zh-CN" => "谢谢。" }

    expect(described_class.resolve(value, locale: :"zh-CN")).to eq("谢谢。")
    expect(described_class.resolve(value, locale: :en)).to eq("Thank you.")
    expect(described_class.resolve({ "en" => "Thank you." }, locale: :"zh-CN")).to eq("Thank you.")
  end

  it "accepts symbol keys and treats a bare string as English" do
    expect(described_class.resolve({ en: "Saved" }, locale: "zh-CN")).to eq("Saved")
    expect(described_class.resolve("Saved", locale: :"zh-CN")).to eq("Saved")
    expect(described_class.resolve(nil, locale: :en)).to eq("")
  end

  it "interpolates named placeholders and leaves unknown tokens intact" do
    expect(described_class.resolve(
      { "en" => "Hi %{name}, unused %{missing}" },
      locale: :en,
      variables: { name: "Ada" }
    )).to eq("Hi Ada, unused %{missing}")
  end

  it "interpolates every locale in a table" do
    expect(described_class.interpolate_each(
      { "en" => "Hi %{name}", "zh-CN" => "你好%{name}" },
      "name" => "Ada"
    )).to eq("en" => "Hi Ada", "zh-CN" => "你好Ada")
  end
end

