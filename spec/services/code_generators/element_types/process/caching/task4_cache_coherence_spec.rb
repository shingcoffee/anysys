# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Task 4 cache tag index coherence" do
  def body(klass, config)
    klass.new({ "config" => config }, {}).generate_body
  end

  let(:write) { CodeGenerators::ElementTypes::Process::Caching::CacheWriteGenerator }
  let(:delete) { CodeGenerators::ElementTypes::Process::Caching::CacheDeleteGenerator }
  let(:fetch) { CodeGenerators::ElementTypes::Process::Caching::CacheFetchGenerator }

  it "writes reverse tag indexes consumed by tagged delete" do
    write_code = body(write, "cacheKey" => "user_1", "action" => "write", "sourceVariable" => "data",
                             "tags" => ["user"])
    expect(write_code).to include('FlowchartRuntime::CacheTags.tag(ctx[:customer_id], cache_key, ["user"]')
    delete_code = body(delete, "scope" => "tagged", "tags" => ["user"])
    expect(delete_code).to include('FlowchartRuntime::CacheTags.invalidate(ctx[:customer_id], "user")')
  end

  it "rejects raw Ruby fallback expressions" do
    errors = fetch.new({ "config" => {} }, {}).validate_config(
      "cacheKey" => "k", "fallbackExpression" => "User.destroy_all", "resultVar" => "r"
    )
    expect(errors.map(&:code)).to include(:invalid_identifier)
  end

  it "does not poke MemoryStore @data for pattern delete" do
    code = body(delete, "scope" => "pattern", "cacheKey" => "user:*")
    expect(code).not_to include("instance_variable_get")
    expect(code).to include("delete_matched")
  end
end
