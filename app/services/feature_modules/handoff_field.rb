# frozen_string_literal: true

module FeatureModules
  # Presentation-facing descriptor of a single handoff-contract field, derived
  # from the Reform-style validations a module declares in its input/output
  # contract (see FeatureModules::BaseModule's `input_contract` / `output_contract`
  # DSL).
  #
  # This is metadata ONLY — runtime validation still runs through the generated
  # Reform::Form. It exists so the platform "Integration Contract" card and the
  # page-builder field-mapping UI can render a rich, single source of truth for
  # what a page must supply to (and receives from) a module, instead of a
  # names-only list.
  class HandoffField
    attr_reader :name, :required, :type, :allowed_values, :constraint, :source

    # definition: { name: "amount_cents", type: "integer", source: "author_only",
    #               validates: { presence: true, ... } }
    def self.from(definition)
      new(name: definition.fetch(:name),
          type: definition[:type],
          source: definition[:source],
          validates: definition[:validates] || {})
    end

    def initialize(name:, validates:, type: nil, source: nil)
      @name           = name.to_s
      @validates      = validates || {}
      @required       = @validates.key?(:presence) && !!@validates[:presence]
      @allowed_values = @validates.dig(:inclusion, :in)
      # A declared type wins; otherwise infer from the validators (back-compat).
      @type           = type.to_s.presence || derive_type
      @source         = (source || "author_only").to_s
      @constraint     = derive_constraint
    end

    def required? = required
    def user_fillable? = @source == "user_fillable"
    def author_only?   = !user_fillable?

    def to_h
      { name: name, required: required, type: type, source: source,
        allowed_values: allowed_values, constraint: constraint }
    end

    private

    def derive_type
      return "enum" if allowed_values

      if (num = @validates[:numericality])
        return (num.is_a?(Hash) && num[:only_integer]) ? "integer" : "number"
      end

      if (fmt = @validates[:format])
        return "email" if format_pattern(fmt) == URI::MailTo::EMAIL_REGEXP
        return "pattern"
      end

      "string"
    end

    # Human-readable extra constraint (allowed values, numeric bounds, regex).
    def derive_constraint
      parts = []
      parts << "one of: #{Array(allowed_values).join(', ')}" if allowed_values

      if (num = @validates[:numericality]).is_a?(Hash)
        parts << "> #{num[:greater_than]}"               if num.key?(:greater_than)
        parts << "≥ #{num[:greater_than_or_equal_to]}"   if num.key?(:greater_than_or_equal_to)
        parts << "< #{num[:less_than]}"                   if num.key?(:less_than)
      end

      if (fmt = @validates[:format])
        pattern = format_pattern(fmt)
        if pattern.respond_to?(:source) && pattern != URI::MailTo::EMAIL_REGEXP
          parts << "matches #{pattern.source}"
        end
      end

      parts.join(" · ").presence
    end

    def format_pattern(fmt)
      fmt.is_a?(Hash) ? fmt[:with] : fmt
    end
  end
end
