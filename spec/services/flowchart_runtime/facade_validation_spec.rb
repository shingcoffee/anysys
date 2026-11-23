# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FlowchartRuntime facade input validation" do
  cases = {
    "archive format" => [FlowchartRuntime::Archive::Error, -> { FlowchartRuntime::Archive.compress([], format: nil) }],
    "archive compression" => [FlowchartRuntime::Archive::Error, -> { FlowchartRuntime::Archive.compress([], compression_level: 10) }],
    "barcode data" => [FlowchartRuntime::Barcode::Error, -> { FlowchartRuntime::Barcode.generate("") }],
    "barcode dimensions" => [FlowchartRuntime::Barcode::Error, -> { FlowchartRuntime::Barcode.generate("x", width: 0) }],
    "xlsx sheet name" => [FlowchartRuntime::FileGenerate::Error, -> { FlowchartRuntime::FileGenerate.xlsx(data: [], sheet_name: "") }],
    "xlsx invalid sheet name" => [FlowchartRuntime::FileGenerate::Error, -> {
      FlowchartRuntime::FileGenerate.xlsx(data: [], sheet_name: "bad/name")
    }],
    "pdf page size" => [FlowchartRuntime::FileGenerate::Error, -> { FlowchartRuntime::FileGenerate.pdf(data: [], page_size: "tabloid") }],
    "xml root" => [FlowchartRuntime::FileGenerate::Error, -> { FlowchartRuntime::FileGenerate.xml(data: [], root_element: "") }],
    "xml item" => [FlowchartRuntime::FileGenerate::Error, -> { FlowchartRuntime::FileGenerate.xml(data: ["bad"], root_element: "root") }],
    "attachment filename" => [FlowchartRuntime::FileGenerate::Error, -> { FlowchartRuntime::FileGenerate.attach_active_storage("x", filename: "") }],
    "hash diff operands" => [FlowchartRuntime::HashDiff::Error, -> { FlowchartRuntime::HashDiff.diff(nil, {}) }],
    "jwt payload" => [FlowchartRuntime::Jwt::Error, -> { FlowchartRuntime::Jwt.encode("payload", "secret") }],
    "jwt secret" => [FlowchartRuntime::Jwt::Error, -> { FlowchartRuntime::Jwt.encode({}, "") }],
    "jwt token" => [FlowchartRuntime::Jwt::Error, -> { FlowchartRuntime::Jwt.decode("", "secret") }],
    "parallel collection" => [FlowchartRuntime::ParallelMap::Error, -> { FlowchartRuntime::ParallelMap.map(nil, in_threads: 1) { |value| value } }],
    "parallel thread count" => [FlowchartRuntime::ParallelMap::Error, -> { FlowchartRuntime::ParallelMap.map([], in_threads: 0) { |value| value } }],
    "qr dimensions" => [FlowchartRuntime::QrCode::Error, -> { FlowchartRuntime::QrCode.generate("x", size: 0) }],
    "qr color" => [FlowchartRuntime::QrCode::Error, -> {
      FlowchartRuntime::QrCode.generate("x", color_dark: "not-a-color")
    }],
    "context scalar traversal" => [FlowchartRuntime::ContextResolver::Error, -> {
      FlowchartRuntime::ContextResolver.resolve("ctx.user.id", { user: "scalar" })
    }],
    "lock ttl" => [FlowchartRuntime::Lock::Error, -> {
      FlowchartRuntime::Lock.acquire("tenant", "key", "token", ttl: 0)
    }],
    "lock token" => [FlowchartRuntime::Lock::Error, -> {
      FlowchartRuntime::Lock.acquire("tenant", "key", "", ttl: 1)
    }],
    "template variables" => [FlowchartRuntime::Template::Error, -> { FlowchartRuntime::Template.render("x", nil) }],
    "toml input" => [FlowchartRuntime::Toml::Error, -> { FlowchartRuntime::Toml.generate([]) }]
  }

  cases.each do |label, (error_class, invocation)|
    it "rejects invalid #{label} before dependency execution" do
      expect(&invocation).to raise_error(error_class)
    end
  end
end
