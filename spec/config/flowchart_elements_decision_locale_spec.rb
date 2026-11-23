# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe "flowchart decision element locales" do
  def flatten(node, prefix = nil)
    return { prefix => node } unless node.is_a?(Hash)

    node.each_with_object({}) do |(key, value), acc|
      path = prefix ? "#{prefix}.#{key}" : key.to_s
      acc.merge!(flatten(value, path))
    end
  end

  let(:english) do
    YAML.safe_load_file(Rails.root.join("config/locales/flowchart_elements_decision.en.yml"))
      .fetch("en").fetch("flowchart_elements").fetch("decision")
  end
  let(:chinese) do
    YAML.safe_load_file(Rails.root.join("config/locales/flowchart_elements_decision.zh-CN.yml"))
      .fetch("zh-CN").fetch("flowchart_elements").fetch("decision")
  end

  it "keeps English and Simplified Chinese key sets identical" do
    expect(flatten(chinese).keys.sort).to eq(flatten(english).keys.sort)
  end

  it "keeps identical interpolation variables in both locales" do
    flatten(english).each do |key, value|
      next unless value.is_a?(String)

      english_vars = value.scan(/%\{(\w+)\}/).flatten.sort
      chinese_vars = flatten(chinese).fetch(key).to_s.scan(/%\{(\w+)\}/).flatten.sort
      expect(chinese_vars).to eq(english_vars), "#{key} interpolation mismatch"
    end
  end

  it "keeps the English option labels the editor stores as Value and Yes / No" do
    expect(english.fetch("fields").fetch("routeBy").fetch("options")).to eq(
      "value" => "Value",
      "condition" => "Yes / No"
    )
  end
end
