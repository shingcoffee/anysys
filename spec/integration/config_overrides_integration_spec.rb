# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Config overrides integration", type: :model do
  describe "ConfigResolver with enriched context" do
    it "resolves role-based override" do
      config = {
        "pageSize" => 25,
        "queryType" => "where",
        "overrides" => [
          { "when" => { "role" => "admin" }, "apply" => { "pageSize" => 100 } },
          { "when" => { "role" => "member" }, "apply" => { "pageSize" => 10 } }
        ]
      }

      admin_result = FlowchartRuntime::ConfigResolver.resolve(config, { current_user_role: "admin", device_type: "desktop" })
      member_result = FlowchartRuntime::ConfigResolver.resolve(config, { current_user_role: "member", device_type: "desktop" })

      expect(admin_result["pageSize"]).to eq(100)
      expect(member_result["pageSize"]).to eq(10)
      expect(admin_result["queryType"]).to eq("where")
    end

    it "resolves device-based override" do
      config = {
        "columns" => 4,
        "overrides" => [
          { "when" => { "device" => "mobile" }, "apply" => { "columns" => 1 } },
          { "when" => { "device" => "tablet" }, "apply" => { "columns" => 2 } }
        ]
      }

      expect(FlowchartRuntime::ConfigResolver.resolve(config, { device_type: "mobile" })["columns"]).to eq(1)
      expect(FlowchartRuntime::ConfigResolver.resolve(config, { device_type: "tablet" })["columns"]).to eq(2)
      expect(FlowchartRuntime::ConfigResolver.resolve(config, { device_type: "desktop" })["columns"]).to eq(4)
    end

    it "resolves condition-based override" do
      config = {
        "showDetails" => false,
        "overrides" => [
          { "when" => { "condition" => "ctx.premium_account" }, "apply" => { "showDetails" => true } }
        ]
      }

      expect(FlowchartRuntime::ConfigResolver.resolve(config, { premium_account: true })["showDetails"]).to be true
      expect(FlowchartRuntime::ConfigResolver.resolve(config, { premium_account: false })["showDetails"]).to be false
    end

    it "applies last-write-wins for conflicting overrides" do
      config = {
        "limit" => 50,
        "overrides" => [
          { "when" => { "role" => "admin" }, "apply" => { "limit" => 200 } },
          { "when" => { "device" => "mobile" }, "apply" => { "limit" => 20 } }
        ]
      }
      ctx = { current_user_role: "admin", device_type: "mobile" }
      expect(FlowchartRuntime::ConfigResolver.resolve(config, ctx)["limit"]).to eq(20)
    end

    it "deep merges nested configuration" do
      config = {
        "queryConfig" => { "limit" => 100, "orderBy" => "name", "filter" => { "status" => "all" } },
        "overrides" => [
          { "when" => { "role" => "admin" }, "apply" => { "queryConfig" => { "limit" => 1000, "filter" => { "status" => "active" } } } }
        ]
      }
      result = FlowchartRuntime::ConfigResolver.resolve(config, { current_user_role: "admin" })

      expect(result["queryConfig"]["limit"]).to eq(1000)
      expect(result["queryConfig"]["orderBy"]).to eq("name")
      expect(result["queryConfig"]["filter"]["status"]).to eq("active")
    end
  end
end
