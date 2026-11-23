# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::ContextResolver do
  describe ".resolve" do
    # ── nil / blank passthrough ──────────────────────────────────────────────

    context "with nil value" do
      it "returns nil" do
        expect(described_class.resolve(nil, {})).to be_nil
      end
    end

    context "with empty string" do
      it "returns empty string" do
        expect(described_class.resolve("", {})).to eq("")
      end
    end

    # ── ctx. references ──────────────────────────────────────────────────────

    context "with a simple ctx reference" do
      it "resolves top-level key" do
        ctx = { status: "approved" }
        expect(described_class.resolve("ctx.status", ctx)).to eq("approved")
      end

      it "returns nil when the key is absent" do
        expect(described_class.resolve("ctx.missing", {})).to be_nil
      end
    end

    context "with a nested ctx reference" do
      it "digs through nested hashes" do
        ctx = { record: { name: "Alice" } }
        expect(described_class.resolve("ctx.record.name", ctx)).to eq("Alice")
      end

      it "returns nil when an intermediate key is absent" do
        ctx = { record: nil }
        expect(described_class.resolve("ctx.record.name", ctx)).to be_nil
      end

      it "normalizes a nested path through a scalar as ContextResolver::Error" do
        expect { described_class.resolve("ctx.user.id", { user: "scalar" }) }
          .to raise_error(described_class::Error, /cannot resolve/)
      end
    end

    context "with an array index in the ctx path" do
      it "accesses the element by integer index" do
        ctx = { items: [{ name: "First" }, { name: "Second" }] }
        expect(described_class.resolve("ctx.items.0.name", ctx)).to eq("First")
        expect(described_class.resolve("ctx.items.1.name", ctx)).to eq("Second")
      end
    end

    # ── template interpolation ───────────────────────────────────────────────

    # NOTE: template strings use single quotes to prevent Ruby from
    # misinterpreting #{{ as the start of a string interpolation expression.

    context "with template interpolation" do
      it "replaces a single {{ctx.field}} placeholder" do
        ctx = { name: "Alice" }
        expect(described_class.resolve('Hello {{ctx.name}}', ctx)).to eq("Hello Alice")
      end

      it "replaces multiple placeholders in one string" do
        ctx      = { name: "Alice", order_id: "ORD-99" }
        template = 'Hello {{ctx.name}}, your order #{{ctx.order_id}}'
        expect(described_class.resolve(template, ctx)).to eq("Hello Alice, your order #ORD-99")
      end

      it "renders an empty string for a missing ctx key inside a template" do
        ctx = {}
        expect(described_class.resolve('Hi {{ctx.name}}!', ctx)).to eq("Hi !")
      end

      it "resolves nested paths inside templates" do
        ctx = { user: { first: "Bob" } }
        expect(described_class.resolve('Hey {{ctx.user.first}}', ctx)).to eq("Hey Bob")
      end
    end

    # ── special values ───────────────────────────────────────────────────────

    context "with special boolean/nil values" do
      it 'returns true for "$true"' do
        expect(described_class.resolve("$true", {})).to be true
      end

      it 'returns false for "$false"' do
        expect(described_class.resolve("$false", {})).to be false
      end

      it 'returns nil for "$nil"' do
        expect(described_class.resolve("$nil", {})).to be_nil
      end
    end

    # ── number coercion ───────────────────────────────────────────────────────

    context "with numeric strings" do
      it "coerces integer strings" do
        expect(described_class.resolve("42", {})).to eq(42)
        expect(described_class.resolve("42", {})).to be_a(Integer)
      end

      it "coerces negative integer strings" do
        expect(described_class.resolve("-7", {})).to eq(-7)
      end

      it "coerces float strings" do
        expect(described_class.resolve("3.14", {})).to eq(3.14)
        expect(described_class.resolve("3.14", {})).to be_a(Float)
      end

      it "coerces negative float strings" do
        expect(described_class.resolve("-0.5", {})).to eq(-0.5)
      end
    end

    # ── literal passthrough ───────────────────────────────────────────────────

    context "with a plain literal string" do
      it "returns the string unchanged" do
        expect(described_class.resolve("hello", {})).to eq("hello")
        expect(described_class.resolve("some_label", {})).to eq("some_label")
      end
    end

    context "with a non-string primitive" do
      it "returns the value as-is" do
        expect(described_class.resolve(123, {})).to eq(123)
        expect(described_class.resolve(true, {})).to be true
        expect(described_class.resolve(false, {})).to be false
      end
    end

    # ── Hash resolution ───────────────────────────────────────────────────────

    context "with a Hash value" do
      it "recursively resolves all values" do
        ctx   = { status: "active" }
        input = { state: "ctx.status", total: "10", label: "hello" }

        result = described_class.resolve(input, ctx)

        expect(result).to eq({ state: "active", total: 10, label: "hello" })
      end

      it "handles nested hashes" do
        ctx   = { name: "Alice" }
        input = { user: { greeting: 'Hello {{ctx.name}}' } }

        result = described_class.resolve(input, ctx)

        expect(result[:user][:greeting]).to eq("Hello Alice")
      end
    end

    # ── Array resolution ──────────────────────────────────────────────────────

    context "with an Array value" do
      it "recursively resolves all elements" do
        ctx   = { tag: "vip" }
        input = ["ctx.tag", "$true", "42", "literal"]

        result = described_class.resolve(input, ctx)

        expect(result).to eq(["vip", true, 42, "literal"])
      end

      it "handles arrays of hashes" do
        ctx   = { name: "Bob" }
        input = [{ label: "ctx.name" }, { flag: "$false" }]

        result = described_class.resolve(input, ctx)

        expect(result).to eq([{ label: "Bob" }, { flag: false }])
      end
    end
  end

  # ── resolve_all ─────────────────────────────────────────────────────────────

  describe ".resolve_all" do
    it "resolves all values in a config hash" do
      ctx = { status: "approved", user: { name: "Carol" } }

      config = {
        state:    "ctx.status",
        greeting: 'Hi {{ctx.user.name}}',
        enabled:  "$true",
        label:    "static"
      }

      result = described_class.resolve_all(config, ctx)

      expect(result[:state]).to    eq("approved")
      expect(result[:greeting]).to eq("Hi Carol")
      expect(result[:enabled]).to  be true
      expect(result[:label]).to    eq("static")
    end

    it "resolves ctx references that exist as symbols" do
      ctx    = { limit: 100 }
      result = described_class.resolve_all({ cap: "ctx.limit" }, ctx)
      expect(result[:cap]).to eq(100)
    end

    it "returns an empty hash when given nil" do
      expect(described_class.resolve_all(nil, {})).to eq({})
    end

    it "returns an empty hash when given a non-hash" do
      expect(described_class.resolve_all("not_a_hash", {})).to eq({})
    end

    it "resolves deeply nested config values" do
      ctx    = { role: "admin" }
      config = { meta: { access: "ctx.role", flag: "$false" } }

      result = described_class.resolve_all(config, ctx)

      expect(result[:meta][:access]).to eq("admin")
      expect(result[:meta][:flag]).to   be false
    end
  end
end
