# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::ConfigResolver do
  describe ".resolve" do
    it "returns base config when no overrides" do
      result = described_class.resolve({ "pageSize" => 25 }, {})
      expect(result).to eq({ "pageSize" => 25 })
    end

    it "returns base config when overrides empty" do
      result = described_class.resolve({ "pageSize" => 25, "overrides" => [] }, {})
      expect(result).to eq({ "pageSize" => 25 })
    end

    it "strips overrides key from result" do
      config = { "x" => 1, "overrides" => [{ "when" => { "role" => "z" }, "apply" => { "x" => 2 } }] }
      result = described_class.resolve(config, {})
      expect(result).not_to have_key("overrides")
    end

    context "role matching" do
      let(:config) { { "p" => 25, "overrides" => [{ "when" => { "role" => "admin" }, "apply" => { "p" => 100 } }] } }

      it "applies when role matches" do
        expect(described_class.resolve(config, { current_user_role: "admin" })["p"]).to eq(100)
      end

      it "skips when role does not match" do
        expect(described_class.resolve(config, { current_user_role: "member" })["p"]).to eq(25)
      end
    end

    context "device matching" do
      let(:config) { { "p" => 25, "overrides" => [{ "when" => { "device" => "mobile" }, "apply" => { "p" => 10 } }] } }

      it "applies when device matches" do
        expect(described_class.resolve(config, { device_type: "mobile" })["p"]).to eq(10)
      end

      it "skips when device does not match" do
        expect(described_class.resolve(config, { device_type: "desktop" })["p"]).to eq(25)
      end
    end

    context "condition matching" do
      let(:config) { { "p" => 25, "overrides" => [{ "when" => { "condition" => "ctx.vip" }, "apply" => { "p" => 50 } }] } }

      it "applies when condition is truthy" do
        expect(described_class.resolve(config, { vip: true })["p"]).to eq(50)
      end

      it "skips when condition is falsy" do
        expect(described_class.resolve(config, { vip: false })["p"]).to eq(25)
      end

      it "skips when condition field is nil" do
        expect(described_class.resolve(config, {})["p"]).to eq(25)
      end

      it "normalizes ContextResolver errors" do
        invalid = {
          "p" => 25,
          "overrides" => [
            { "when" => { "condition" => "ctx.user.name" }, "apply" => { "p" => 50 } }
          ]
        }

        expect {
          described_class.resolve(invalid, { user: "not-a-hash" })
        }.to raise_error(described_class::Error, /cannot resolve/)
      end
    end

    context "combined AND" do
      it "applies only when all match" do
        config = { "p" => 25, "overrides" => [{ "when" => { "role" => "admin", "device" => "mobile" }, "apply" => { "p" => 5 } }] }
        expect(described_class.resolve(config, { current_user_role: "admin", device_type: "mobile" })["p"]).to eq(5)
        expect(described_class.resolve(config, { current_user_role: "admin", device_type: "desktop" })["p"]).to eq(25)
      end
    end

    context "last-write-wins" do
      it "later overrides take precedence" do
        config = {
          "p" => 25,
          "overrides" => [
            { "when" => { "role" => "admin" }, "apply" => { "p" => 100 } },
            { "when" => { "device" => "mobile" }, "apply" => { "p" => 10 } }
          ]
        }
        expect(described_class.resolve(config, { current_user_role: "admin", device_type: "mobile" })["p"]).to eq(10)
      end

      it "non-conflicting keys merge" do
        config = {
          "a" => 1, "b" => 2,
          "overrides" => [
            { "when" => { "role" => "admin" }, "apply" => { "a" => 10 } },
            { "when" => { "device" => "mobile" }, "apply" => { "b" => 20 } }
          ]
        }
        result = described_class.resolve(config, { current_user_role: "admin", device_type: "mobile" })
        expect(result["a"]).to eq(10)
        expect(result["b"]).to eq(20)
      end
    end

    context "deep merge" do
      it "deep merges nested hashes" do
        config = {
          "q" => { "limit" => 100, "order" => "name" },
          "overrides" => [{ "when" => { "role" => "admin" }, "apply" => { "q" => { "limit" => 500 } } }]
        }
        result = described_class.resolve(config, { current_user_role: "admin" })
        expect(result["q"]["limit"]).to eq(500)
        expect(result["q"]["order"]).to eq("name")
      end
    end

    context "edge cases" do
      it("handles nil config") { expect(described_class.resolve(nil, {})).to eq({}) }
      it("handles empty config") { expect(described_class.resolve({}, {})).to eq({}) }
    end
  end
end
