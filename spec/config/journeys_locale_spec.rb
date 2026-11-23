# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe "journey locales" do
  let(:english) { YAML.safe_load_file(Rails.root.join("config/locales/journeys.en.yml")).fetch("en") }
  let(:chinese) { YAML.safe_load_file(Rails.root.join("config/locales/journeys.zh-CN.yml")).fetch("zh-CN") }

  def flatten_keys(value, prefix = nil)
    return [prefix] unless value.is_a?(Hash)

    value.flat_map { |key, item| flatten_keys(item, [prefix, key].compact.join(".")) }
  end

  it "keeps keys and interpolation variables in parity" do
    expect(flatten_keys(chinese).sort).to eq(flatten_keys(english).sort)
    flatten_keys(english).each do |key|
      variables = ->(tree) { tree.dig(*key.split(".")).to_s.scan(/%\{(\w+)\}/).flatten.sort }
      expect(variables.call(chinese)).to eq(variables.call(english)), key
    end
  end

  it "names journey attributes in both locales" do
    expect(Journey.human_attribute_name(:key, locale: :en)).to eq("Key")
    expect(Journey.human_attribute_name(:key, locale: :"zh-CN")).to eq("标识")
  end
end
