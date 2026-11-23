# frozen_string_literal: true

require "rails_helper"

RSpec.describe "flowchart_actions_model_queries locales" do
  def flatten_keys(hash, prefix = [])
    hash.flat_map do |key, value|
      path = prefix + [key]
      value.is_a?(Hash) ? flatten_keys(value, path) : [path.join(".")]
    end
  end

  def interpolations(hash)
    hash.each_with_object({}) do |(key, value), acc|
      if value.is_a?(Hash)
        interpolations(value).each { |child, tokens| acc["#{key}.#{child}"] = tokens }
      elsif value.is_a?(String)
        acc[key] = value.scan(/%\{(\w+)\}/).flatten
      end
    end
  end

  it "keeps English and zh-CN keys and interpolations in parity" do
    english = YAML.safe_load_file(Rails.root.join("config/locales/flowchart_actions_model_queries.en.yml")).fetch("en")
    chinese = YAML.safe_load_file(Rails.root.join("config/locales/flowchart_actions_model_queries.zh-CN.yml")).fetch("zh-CN")

    expect(flatten_keys(chinese).sort).to eq(flatten_keys(english).sort)
    expect(interpolations(chinese)).to eq(interpolations(english))
  end
end
