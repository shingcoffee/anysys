# frozen_string_literal: true

# Tiny ported generator used by Wave 1 catalog/role specs. Not registered.
class Phase3FixtureGenerator < CodeGenerators::BaseGenerator
  def self.name
    "CodeGenerators::ElementTypes::Process::Utility::Phase3FixtureGenerator"
  end

  generator_metadata do
    description "Phase 3 Wave 1 fixture"
    category :utility
    version "1.0.0"
    presentation icon: "circle", color: "blue", single_use: false, privileged: false
  end

  config_schema do
    input :sourceVariable, required: true, example: "order.items"
    output :resultVar, default: "total"
    expression :predicate, required: true, example: "item[:qty] > 0"
    literal :label, default: "Total", max_length: 40
    template :message, default: "Hello {{name}}"
    enum :operation, %w[sum avg], default: "sum"
    flag :skipNil, default: true
    integer :limit, min: 1, max: 10, default: 3
    decimal :rate, min: 0, max: 1, default: 0.1
    list :tags, item: :literal, default: []
    mapping :aliases, key: :literal, value: :input, default: []
    conditions :filter, default: { "type" => "group", "joins" => [], "conditions" => [] }
    entity_attribute :amountField, of: :bound, default: "amount"
    reference :templateId, source: :email_templates
    localized_text :title, default: { "en" => "Title" }
    enum :rateSource, %w[fixed live], default: "live"
    literal :fixedRate, default: "1.0"
    requires :fixedRate, when: { rateSource: "fixed" }
    literal :idempotencyKey
    transport_retry idempotent_when: { operation: %w[sum] }, or_present: :idempotencyKey
    timeouts open: 3, read: 7
    circuit_breaker_option
  end

  def generate_body
    body(
      assign(:resultVar, read(:sourceVariable)),
      fail_with(:empty, field: :sourceVariable, unless: read(:sourceVariable)),
      "true"
    )
  end
end
