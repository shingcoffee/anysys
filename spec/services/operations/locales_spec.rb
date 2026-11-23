# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe "operations locales" do
  def flatten(value, path = [])
    case value
    when Hash then value.flat_map { |key, item| flatten(item, path + [key.to_s]) }
    else [[path.join("."), value.to_s.scan(/%\{([^}]+)\}/).flatten.sort]]
    end
  end

  let(:english) do
    YAML.safe_load_file(Rails.root.join("config/locales/operations.en.yml")).fetch("en").fetch("operations")
  end
  let(:chinese) do
    YAML.safe_load_file(Rails.root.join("config/locales/operations.zh-CN.yml")).fetch("zh-CN").fetch("operations")
  end

  it "keeps English and Simplified Chinese leaf keys and interpolation variables in parity" do
    expect(flatten(english).to_h).to eq(flatten(chinese).to_h)
  end
end
