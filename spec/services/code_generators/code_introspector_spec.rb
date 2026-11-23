# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::CodeIntrospector do
  describe ".analyze" do
    it "returns hash with inputs and outputs arrays" do
      result = described_class.analyze("ctx[:result] = ctx[:input]")
      expect(result).to be_a(Hash)
      expect(result[:inputs]).to be_an(Array)
      expect(result[:outputs]).to be_an(Array)
    end

    it "detects ctx[:key] = as output" do
      result = described_class.analyze("ctx[:result] = User.find(1)")
      expect(result[:outputs]).to eq(["result"])
    end

    it "detects ctx[:key] read as input" do
      result = described_class.analyze("name = ctx[:user_name]")
      expect(result[:inputs]).to eq(["user_name"])
    end

    it "detects ctx.dig(:key, ...) as input (top-level key only)" do
      result = described_class.analyze("val = ctx.dig(:config, :timeout)")
      expect(result[:inputs]).to eq(["config"])
    end

    it "detects ctx.fetch(:key) as input" do
      result = described_class.analyze("val = ctx.fetch(:model)")
      expect(result[:inputs]).to eq(["model"])
    end

    it "detects ctx.fetch(:key, default) as input" do
      result = described_class.analyze("val = ctx.fetch(:retries, 3)")
      expect(result[:inputs]).to eq(["retries"])
    end

    it "excludes keys starting with _" do
      result = described_class.analyze("ctx[:_internal] = 1\nval = ctx[:_route]")
      expect(result[:inputs]).to be_empty
      expect(result[:outputs]).to be_empty
    end

    it "lists key in both inputs and outputs when read and written" do
      result = described_class.analyze("ctx[:counter] = ctx[:counter] + 1")
      expect(result[:inputs]).to include("counter")
      expect(result[:outputs]).to include("counter")
    end

    it "excludes keys inside string literals" do
      code = '"ctx[:not_real] = something"'
      result = described_class.analyze(code)
      expect(result[:inputs]).to be_empty
      expect(result[:outputs]).to be_empty
    end

    it "excludes keys inside single-quoted strings" do
      code = "'ctx[:not_real] = something'"
      result = described_class.analyze(code)
      expect(result[:inputs]).to be_empty
      expect(result[:outputs]).to be_empty
    end

    it "excludes keys inside comments" do
      code = "# ctx[:commented] = something\nctx[:real] = 1"
      result = described_class.analyze(code)
      expect(result[:outputs]).to eq(["real"])
      expect(result[:inputs]).to be_empty
    end

    it "deduplicates keys" do
      code = "x = ctx[:model]\ny = ctx[:model]\nctx[:result] = x"
      result = described_class.analyze(code)
      expect(result[:inputs]).to eq(["model"])
      expect(result[:outputs]).to eq(["result"])
    end

    it "returns empty arrays for nil input" do
      result = described_class.analyze(nil)
      expect(result).to eq({ inputs: [], outputs: [] })
    end

    it "returns empty arrays for empty string" do
      result = described_class.analyze("")
      expect(result).to eq({ inputs: [], outputs: [] })
    end

    it "handles heredoc strings" do
      code = <<~'RUBY'
        sql = <<~SQL
          SELECT ctx[:not_real] FROM users
        SQL
        ctx[:result] = ActiveRecord::Base.connection.execute(sql)
      RUBY
      result = described_class.analyze(code)
      expect(result[:outputs]).to eq(["result"])
      expect(result[:inputs]).not_to include("not_real")
    end
  end
end
