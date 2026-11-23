# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe "operations contract lint" do
  let_it_be(:customer) { create(:customer) }
  let(:context) { Operations::Context.new(customer: customer, channel: "assistant") }

  it "has an empty SchemaLint report for every registered operation" do
    expect(Operations.keys.map(&:to_s)).to include("create_domain", "create_entity", "update_entity", "get_entity", "set_page_processing", "start_subsystem_build")
    expect(Operations.keys.map(&:to_s)).not_to include("list_journey_options", "generate_journeys")

    Operations.all.each do |operation|
      problems = Operations::SchemaLint.call(operation, context)
      expect(problems).to eq([]), "#{operation.key}: #{problems.join("; ")}"
    end
  end

  def flatten_locale(value, path = [])
    case value
    when Hash then value.flat_map { |key, item| flatten_locale(item, path + [key.to_s]) }
    else [[path.join("."), value.to_s.scan(/%\{([^}]+)\}/).flatten.sort]]
    end
  end

  %w[operations_entity operations_journey operations_page operations_subsystem].each do |area|
    it "keeps #{area} locale keys and interpolations in parity" do
      english = YAML.safe_load_file(Rails.root.join("config/locales/#{area}.en.yml")).fetch("en").fetch("operations")
      chinese = YAML.safe_load_file(Rails.root.join("config/locales/#{area}.zh-CN.yml")).fetch("zh-CN").fetch("operations")
      expect(flatten_locale(english).to_h).to eq(flatten_locale(chinese).to_h)
    end
  end
end
