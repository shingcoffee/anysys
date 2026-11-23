# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::Shared::IdentifierSanitizer do
  let(:host) do
    Class.new do
      include CodeGenerators::Shared::IdentifierSanitizer
    end.new
  end

  describe "#safe_ident?" do
    it "accepts a plain lowercase identifier" do
      expect(host.safe_ident?("my_var")).to be true
    end

    it "accepts an identifier starting with underscore" do
      expect(host.safe_ident?("_private")).to be true
    end

    it "accepts mixed-case identifiers" do
      expect(host.safe_ident?("myVar123")).to be true
    end

    it "rejects an empty string" do
      expect(host.safe_ident?("")).to be false
    end

    it "rejects a string starting with a digit" do
      expect(host.safe_ident?("1abc")).to be false
    end

    it "rejects a string starting with uppercase" do
      expect(host.safe_ident?("MyClass")).to be false
    end

    it "rejects strings with special characters" do
      expect(host.safe_ident?("my-var")).to be false
      expect(host.safe_ident?("my var")).to be false
    end

    it "rejects Ruby reserved words" do
      expect(host.safe_ident?("if")).to be false
      expect(host.safe_ident?("class")).to be false
      expect(host.safe_ident?("def")).to be false
      expect(host.safe_ident?("nil")).to be false
      expect(host.safe_ident?("return")).to be false
    end
  end

  describe "#safe_ctx_read" do
    it "emits ctx[:name] for a safe identifier" do
      expect(host.safe_ctx_read("order")).to eq("ctx[:order]")
    end

    it "emits nil for an unsafe identifier" do
      expect(host.safe_ctx_read("bad-key")).to eq("nil")
    end

    it "emits nil for a reserved word" do
      expect(host.safe_ctx_read("class")).to eq("nil")
    end
  end

  describe "#safe_ctx_assign" do
    it "emits ctx[:name] = expr for a safe identifier" do
      expect(host.safe_ctx_assign("result", "42")).to eq("ctx[:result] = 42")
    end

    it "emits a TODO comment for an unsafe identifier" do
      code = host.safe_ctx_assign("bad-key", "42")
      expect(code).to start_with("# TODO: skipped assignment")
      expect(code).to include("bad-key")
    end
  end

  describe "#safe_string_literal" do
    it "returns a Ruby string literal (inspect)" do
      expect(host.safe_string_literal("hello")).to eq('"hello"')
    end

    it "escapes embedded quotes" do
      expect(host.safe_string_literal('say "hi"')).to eq('"say \\"hi\\""')
    end

    it "handles non-string input by calling to_s" do
      expect(host.safe_string_literal(42)).to eq('"42"')
    end
  end

  describe "#strip_control_chars" do
    it "removes newlines and carriage returns" do
      result = host.strip_control_chars("line1\r\nline2")
      expect(result).not_to include("\r")
      expect(result).not_to include("\n")
    end

    it "removes null bytes" do
      result = host.strip_control_chars("val\x00ue")
      expect(result).not_to include("\x00")
    end

    it "leaves normal strings unchanged" do
      expect(host.strip_control_chars("normal")).to eq("normal")
    end
  end

  describe "#safe_constant" do
    let(:allowlist) { %w[String Integer MyClass] }

    it "returns the constant name for an allowlisted constant" do
      expect(host.safe_constant("String", allowlist: allowlist)).to eq("String")
    end

    it "returns nil for a non-allowlisted constant" do
      expect(host.safe_constant("Kernel", allowlist: allowlist)).to be_nil
    end

    it "returns nil for a lowercase name (fails CONST_RE)" do
      expect(host.safe_constant("string", allowlist: allowlist)).to be_nil
    end

    it "strips surrounding whitespace before checking" do
      expect(host.safe_constant("  String  ", allowlist: allowlist)).to eq("String")
    end
  end
end
