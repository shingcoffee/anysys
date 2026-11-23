# frozen_string_literal: true

module GeneratorConformance
  # Fields whose variation legitimately produces no emitted-source delta.
  #
  # Every entry MUST carry a written justification explaining the mechanism
  # that prevents the field from reaching generate_body. An entry without a
  # real reason is a laundered defect, not an exception.
  #
  # Shape: { "action_key" => { "fieldKey" => "justification" } }
  INERT_FIELD_ALLOWLIST = {}.freeze

  # Enum selects whose options legitimately emit byte-identical source.
  #
  # Every entry MUST name the exact colliding options and explain the
  # MECHANISM that makes the collision correct — i.e. why the two options are
  # observably different to the operator despite the generator emitting the
  # same bytes. "Does not affect output" is not a justification; if the emitted
  # code is the same and nothing else distinguishes the options, the redundant
  # option must be removed from the property editor instead.
  #
  # Shape:
  #   { "action_key" => { "fieldKey" => { options: [...], reason: "..." } } }
  DUPLICATE_ENUM_OPTION_ALLOWLIST = {}.freeze
end
