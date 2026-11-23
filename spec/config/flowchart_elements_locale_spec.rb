# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe "flowchart structural element locales" do
  let(:english) do
    YAML.safe_load_file(Rails.root.join("config/locales/flowchart_elements.en.yml")).fetch("en").fetch("flowchart_elements")
  end
  let(:chinese) do
    YAML.safe_load_file(Rails.root.join("config/locales/flowchart_elements.zh-CN.yml")).fetch("zh-CN").fetch("flowchart_elements")
  end

  def flatten_keys(value, prefix = nil)
    case value
    when Hash
      value.flat_map { |key, item| flatten_keys(item, [prefix, key].compact.join(".")) }
    else
      [prefix]
    end
  end

  it "keeps English and Simplified Chinese key sets identical" do
    expect(flatten_keys(chinese).sort).to eq(flatten_keys(english).sort)
  end

  Dir[Rails.root.join("config/locales/flowchart_elements_*.en.yml")].each do |english_path|
    chinese_path = english_path.sub(/\.en\.yml\z/, ".zh-CN.yml")

    it "keeps keys and interpolation variables in parity for #{File.basename(english_path, '.en.yml')}" do
      en = YAML.safe_load_file(english_path).fetch("en")
      zh = YAML.safe_load_file(chinese_path).fetch("zh-CN")
      expect(flatten_keys(zh).sort).to eq(flatten_keys(en).sort)
      flatten_keys(en).each do |key|
        path = key.split(".")
        variables = ->(tree) { tree.dig(*path).to_s.scan(/%\{(\w+)\}/).flatten.sort }
        expect(variables.call(zh)).to eq(variables.call(en)), key
      end
    end
  end

  it "keeps exact English source strings for type labels, chrome, and End options" do
    expect(english.dig("start", "defaultLabel")).to eq("Start")
    expect(english.dig("chrome", "label", "label")).to eq("Label")
    expect(english.dig("end", "fields", "responseType", "options", "none")).to eq("Nothing")
    expect(english.dig("end", "fields", "responseType", "options", "value")).to eq("Return a value")
    expect(english.dig("subflow", "fields", "flowchartId", "label")).to eq("Flowchart")
  end

  it "reuses the existing zh-CN default labels" do
    expect(chinese.dig("start", "defaultLabel")).to eq("开始")
    expect(chinese.dig("end", "defaultLabel")).to eq("结束")
    expect(chinese.dig("process", "defaultLabel")).to eq("流程")
    expect(chinese.dig("decision", "defaultLabel")).to eq("决策")
    expect(chinese.dig("loop", "defaultLabel")).to eq("循环")
    expect(chinese.dig("subflow", "defaultLabel")).to eq("子流程")
  end

  it "does not keep Timer or HTTP response field keys" do
    keys = flatten_keys(english)
    expect(keys.grep(/timer/)).to be_empty
    expect(keys.grep(/http_response|httpStatus|responseBody/)).to be_empty
  end

  it "keeps trace.errors keys identical across locales" do
    expect(chinese.fetch("trace").fetch("errors").keys.sort).to eq(
      english.fetch("trace").fetch("errors").keys.sort
    )
  end
end
