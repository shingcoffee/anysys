# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContextSanitizer do
  describe ".sanitize" do
    it "passes through simple values unchanged" do
      ctx = {
        string: "hello",
        number: 42,
        float: 3.14,
        true_val: true,
        false_val: false,
        nil_val: nil
      }

      result = described_class.sanitize(ctx)

      expect(result[:string]).to eq("hello")
      expect(result[:number]).to eq(42)
      expect(result[:float]).to eq(3.14)
      expect(result[:true_val]).to eq(true)
      expect(result[:false_val]).to eq(false)
      expect(result[:nil_val]).to be_nil
    end

    it "recursively transforms nested hashes" do
      ctx = {
        nested: {
          deep: {
            value: "test"
          }
        }
      }

      result = described_class.sanitize(ctx)

      expect(result[:nested][:deep][:value]).to eq("test")
    end

    it "transforms arrays by inspecting non-hash elements" do
      ctx = {
        items: [1, "two", :three]
      }

      result = described_class.sanitize(ctx)

      expect(result[:items]).to eq(["1", "\"two\"", ":three"])
    end

    it "transforms array elements that are hashes" do
      ctx = {
        items: [{ key: "value" }, { other: 123 }]
      }

      result = described_class.sanitize(ctx)

      expect(result[:items][0]).to eq({ key: "value" })
      expect(result[:items][1]).to eq({ other: 123 })
    end

    it "inspects objects that are not basic types" do
      object = Object.new
      ctx = { object: object }

      result = described_class.sanitize(ctx)

      expect(result[:object]).to eq(object.inspect)
    end

    it "handles complex nested structures" do
      ctx = {
        user: {
          name: "John",
          age: 30,
          roles: [:admin, :user],
          metadata: {
            last_login: Time.now
          }
        }
      }

      result = described_class.sanitize(ctx)

      expect(result[:user][:name]).to eq("John")
      expect(result[:user][:age]).to eq(30)
      expect(result[:user][:roles]).to be_an(Array)
      expect(result[:user][:metadata][:last_login]).to be_a(String)
    end

    it "returns string representation when an error occurs" do
      ctx = double("problematic_context")
      allow(ctx).to receive(:each_with_object).and_raise(StandardError.new("Test error"))
      allow(ctx).to receive(:to_s).and_return("fallback_string")

      result = described_class.sanitize(ctx)

      expect(result).to eq("fallback_string")
    end

    it "handles empty hash" do
      result = described_class.sanitize({})
      expect(result).to eq({})
    end

    it "handles hash with symbol keys" do
      ctx = { symbol_key: "value" }
      result = described_class.sanitize(ctx)
      expect(result[:symbol_key]).to eq("value")
    end

    it "handles hash with string keys" do
      ctx = { "string_key" => "value" }
      result = described_class.sanitize(ctx)
      expect(result["string_key"]).to eq("value")
    end

    it "strips _last_error and other internal underscore keys from snapshots" do
      ctx = {
        name: "visible",
        _last_error: "Kernel.raise leaked",
        "_last_error" => "string-key leak",
        _last_error_class: "RuntimeError",
        nested: { _last_error: "nested leak", ok: 1 },
        items: [{ _last_error: "array leak", keep: true }]
      }

      result = described_class.sanitize(ctx)

      expect(result).to include(name: "visible")
      expect(result).not_to have_key(:_last_error)
      expect(result).not_to have_key("_last_error")
      expect(result).not_to have_key(:_last_error_class)
      expect(result[:nested]).to eq({ ok: 1 })
      expect(result[:items][0]).to eq({ keep: true })
      expect(result.inspect).not_to include("Kernel.raise leaked")
      expect(result.inspect).not_to include("string-key leak")
      expect(result.inspect).not_to include("nested leak")
      expect(result.inspect).not_to include("array leak")
    end
  end
end
