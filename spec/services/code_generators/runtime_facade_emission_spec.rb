# frozen_string_literal: true

require "rails_helper"
load Rails.root.join("scripts/audit_generators.rb")

RSpec.describe "runtime facade generator emission" do
  FACADES = %w[
    Archive Barcode Cipher Clone Crypto FileGenerate HashDiff Id Jwt Lock ParallelMap
    PasswordHash QrCode Sanitize Schedule Template Token Toml
  ].freeze

  it "maps only the exact facade error to Railway failure" do
    defects = []

    GeneratorAudit.send(:generator_files).each do |file|
      generator = GeneratorAudit.send(:load_generator, file)
      next unless generator

      GeneratorAudit.send(:generated_variants, generator).each do |variant|
        next if variant[:generation_error]

        body = variant.fetch(:body)
        next unless body.is_a?(String)

        references = body.scan(/FlowchartRuntime::(#{FACADES.join('|')})\b/).flatten.uniq
        references << "OutboundHttp" if body.include?("OutboundHttp.request")

        references.each do |facade|
          error_classes = if facade == "OutboundHttp"
            %w[OutboundHttp::Error OutboundHttp::TransportError OutboundHttp::ResponseError]
          else
            ["FlowchartRuntime::#{facade}::Error"]
          end
          mapped = error_classes.any? do |error_class|
            body.include?("FlowchartRuntime::Step.attempt") && body.include?(error_class)
          end
          next if mapped && !body.include?("ctx[:_last_error]")

          defects << "#{generator.name} [#{variant.fetch(:label)}] does not map #{error_classes.join('|')} through Step.attempt"
        end
      end
    end

    expect(defects).to be_empty, defects.join("\n")
  end
end
