# frozen_string_literal: true

require "liquid"
require "prism"

module CodeGenerators
  # Declarative configuration schema for generators: role methods (`input`,
  # `output`, `enum`, …) declare each field, `requires` adds conditional
  # requirements and `validate do |cfg, errors| … end` adds bespoke rules.
  class ConfigSchema
    GROUPS = %i[main advanced].freeze
    RUN_LIMIT_SECONDS = 10

    ROLES = %i[
      input output expression literal template enum flag integer decimal
      list mapping conditions entity_attribute reference localized_text
    ].freeze

    # `description` is model-facing English API documentation (the assistant
    # palette), not a UI string; the property editor reads labels and help
    # from flowchart_actions / flowchart_elements locale keys.
    COMMON_OPTIONS = %i[default required example visible group placeholder description].freeze

    ROLE_OPTIONS = {
      input: COMMON_OPTIONS,
      output: COMMON_OPTIONS,
      expression: COMMON_OPTIONS + %i[max_length multiline],
      literal: COMMON_OPTIONS + %i[max_length multiline],
      template: COMMON_OPTIONS + %i[max_length multiline],
      enum: COMMON_OPTIONS + %i[values],
      flag: COMMON_OPTIONS,
      integer: COMMON_OPTIONS + %i[min max],
      decimal: COMMON_OPTIONS + %i[min max],
      list: COMMON_OPTIONS + %i[item],
      mapping: COMMON_OPTIONS + %i[key value],
      conditions: COMMON_OPTIONS,
      entity_attribute: COMMON_OPTIONS + %i[of],
      reference: COMMON_OPTIONS + %i[source],
      localized_text: COMMON_OPTIONS + %i[max_length multiline]
    }.freeze

    SEEDED_KEYS = %w[
      params bound_entity customer_id authentication current_user_id
      current_user_role audience device_type request_ip user_agent locale
      request_id flowchart_id writable_slugs association_params
    ].freeze

    OUTPUT_RESERVED = (
      SEEDED_KEYS + %w[errors error_details submission_outcome result]
    ).freeze

    INPUT_FORBIDDEN_ROOTS = %w[errors error_details submission_outcome result].freeze

    IDENT_SEGMENT = /\A[a-z_][a-zA-Z0-9_]*\z/

    CAPABILITY_FIELDS = {
      transport_retry: %w[retryOnTransportError retryAttempts],
      timeouts: %w[connectTimeout readTimeout],
      circuit_breaker: %w[circuitBreaker breakerName failureThreshold resetTimeoutSeconds]
    }.freeze

    DeclaredField = Data.define(:name, :role, :options, :conditions, :capabilities)

    STRUCTURAL_CONFIG_KEYS = %w[
      description label steps condition io_overrides inputs outputs
    ].freeze
    ELEMENT_I18N_PREFIX = "flowchart_elements"

    def initialize(action_name: nil, i18n_prefix: "flowchart_actions")
      @action_name = action_name.to_s
      @i18n_prefix = i18n_prefix.to_s
      @fields = []
      @validators = []
      @capabilities = {}
      @requires = []
      @declaring_capability = nil
    end

    attr_reader :fields, :validators, :capabilities, :action_name

    def validate(&block)
      @validators << block
    end

    # === Role DSL ===

    ROLES.each do |role|
      define_method(role) do |name, values = nil, **opts|
        if values && !values.is_a?(Hash)
          opts[:values] = values
        elsif values.is_a?(Hash)
          opts = values.merge(opts)
        end
        declare(role, name, opts)
      end
    end

    def requires(name, **opts)
      when_hash = opts[:when]
      raise ArgumentError, "requires :#{name} needs when:" unless when_hash.is_a?(Hash)

      @requires << { field: name.to_s, when: stringify_when(when_hash) }
      refresh_conditions!
    end

    def transport_retry(idempotent_when:, or_present: nil)
      @capabilities[:transport_retry] = {
        idempotent_when: stringify_when(idempotent_when),
        or_present: or_present&.to_s
      }
      with_capability(:transport_retry) do
        flag :retryOnTransportError, default: false, group: :advanced,
          description: "Retry once more when the connection fails before any response arrives. " \
                       "Allowed only for idempotent requests, so a retried call cannot act twice."
        integer :retryAttempts, min: 1, max: 2, default: 1, group: :advanced,
          description: "Extra attempts after a transport failure (1-2) when retryOnTransportError is on."
      end
    end

    def timeouts(open:, read:)
      @capabilities[:timeouts] = { open: open, read: read, cap: RUN_LIMIT_SECONDS }
      with_capability(:timeouts) do
        integer :connectTimeout, min: 1, max: 5, default: open, group: :advanced,
          description: "Seconds to wait for the connection to open (1-5). " \
                       "connectTimeout + readTimeout must stay within #{RUN_LIMIT_SECONDS} seconds."
        integer :readTimeout, min: 1, max: 9, default: read, group: :advanced,
          description: "Seconds to wait for the response once connected (1-9); a slower answer fails the step."
      end
    end

    def circuit_breaker_option
      @capabilities[:circuit_breaker] = true
      with_capability(:circuit_breaker) do
        flag :circuitBreaker, default: false, group: :advanced,
          description: "Stop calling the remote service for a while after repeated failures, " \
                       "failing fast instead of waiting on every run."
        literal :breakerName, default: @action_name, group: :advanced,
          description: "Name of the breaker; steps that call the same service share one name so they trip together."
        integer :failureThreshold, min: 1, max: 20, default: 5, group: :advanced,
          description: "Consecutive failures that open the breaker (1-20)."
        integer :resetTimeoutSeconds, min: 10, max: 3600, default: 60, group: :advanced,
          description: "Seconds the breaker stays open before one trial call is let through (10-3600)."
      end
    end

    def method_missing(name, *args, **kwargs, &block)
      raise ArgumentError, "unknown config_schema role or statement #{name.inspect}"
    end

    def respond_to_missing?(_name, _include_private = false)
      false
    end

    # === Runtime ===

    def validate_config(cfg, context = nil)
      cfg ||= {}
      errors = ErrorCollector.new(self)
      @fields.each { |field| validate_declared_field(field, cfg, errors, context) }
      validate_requires(cfg, errors)
      validate_capabilities(cfg, errors)
      validate_unknown_keys(cfg, errors)
      @validators.each do |validator|
        if context
          context.instance_exec(cfg, errors, &validator)
        else
          validator.call(cfg, errors)
        end
      end
      errors.to_a
    end

    def value(cfg, name)
      field = find_declared(name)
      return lookup(cfg, name) if field.nil?
      return coerce(field, field.options[:default]) unless field_visible?(field, cfg)

      raw = lookup(cfg, name)
      return coerce(field, field.options[:default]) if missing?(raw, field.role)

      coerce(field, raw)
    end

    def defaults
      @fields.each_with_object({}) do |field, hash|
        default = field.options[:default]
        hash[field.name] = default unless default.nil?
      end
    end

    # Every field's default, falling back to its example, whether or not the
    # field is visible under the resulting configuration.
    def examples
      @fields.each_with_object({}) do |field, hash|
        value = field.options[:default]
        value = field.options[:example] if value.nil?
        hash[field.name] = value unless value.nil?
      end
    end

    # The examples for the fields that are visible under that configuration.
    def sample_input
      sample = examples
      sample.select { |name, _value| field_visible?(find_declared(name), sample) }
    end

    def catalog
      @fields.map do |field|
        {
          name: field.name,
          role: field.role,
          options: field.options,
          conditions: field.conditions,
          capabilities: field.capabilities
        }
      end
    end

    def message_for(field, code, **vars)
      vars = vars.merge(field: field.to_s)
      action_key = "#{@i18n_prefix}.#{@action_name}.errors.#{code}"
      shared_key = "#{@i18n_prefix}.shared.errors.#{code}"
      if @action_name.present? && I18n.exists?(action_key)
        I18n.t(action_key, **vars)
      else
        I18n.t(shared_key, **vars)
      end
    end

    def visible_defaults
      acc = {}
      @fields.each do |field|
        next unless field_visible?(field, acc)

        default = field.options[:default]
        acc[field.name] = default unless default.nil?
      end
      acc
    end

    def find_declared(name)
      @fields.find { |field| field.name == name.to_s }
    end

    class ErrorCollector
      def initialize(schema)
        @schema = schema
        @items = []
      end

      def add(field, code, **vars)
        @items << ConfigError.new(
          field: field&.to_s,
          code: code.to_sym,
          message: @schema.message_for(field, code, **vars)
        )
        self
      end

      def <<(item)
        if item.is_a?(ConfigError)
          @items << item
        elsif item.is_a?(String)
          @items << ConfigError.new(field: nil, code: :invalid, message: item)
        else
          @items << item
        end
        self
      end

      def concat(other)
        Array(other).each { |item| self << item }
        self
      end

      def to_a
        @items
      end

      def empty?
        @items.empty?
      end
    end

    private

    def declare(role, name, opts)
      unknown = opts.keys - ROLE_OPTIONS.fetch(role)
      raise ArgumentError, "unknown option #{unknown.inspect} for #{role}" if unknown.any?

      group = opts[:group] || :main
      raise ArgumentError, "group must be :main or :advanced" unless GROUPS.include?(group)

      if role == :enum && Array(opts[:values]).empty?
        raise ArgumentError, "enum :#{name} requires values"
      end

      opts = opts.merge(group: group)
      opts[:visible] = stringify_when(opts[:visible]) if opts[:visible]
      @fields << DeclaredField.new(
        name: name.to_s,
        role: role,
        options: opts,
        conditions: [],
        capabilities: Array(@declaring_capability)
      )
      refresh_conditions!
    end

    def refresh_conditions!
      @fields.map! do |field|
        conditions = []
        if field.options[:visible]
          conditions << { type: :visible, when: field.options[:visible] }
        end
        @requires.select { |rule| rule[:field] == field.name }.each do |rule|
          conditions << { type: :requires, when: rule[:when] }
        end
        DeclaredField.new(
          name: field.name,
          role: field.role,
          options: field.options,
          conditions: conditions,
          capabilities: field.capabilities
        )
      end
    end

    def with_capability(name)
      previous = @declaring_capability
      @declaring_capability = name
      yield
    ensure
      @declaring_capability = previous
    end

    def stringify_when(hash)
      (hash || {}).each_with_object({}) do |(key, value), result|
        result[key.to_s] = value
      end
    end

    def validate_unknown_keys(cfg, errors)
      return unless @i18n_prefix == ELEMENT_I18N_PREFIX
      return unless cfg.respond_to?(:keys)

      declared = @fields.map { |field| field.name.to_s }
      extras = cfg.keys.map(&:to_s) - declared - STRUCTURAL_CONFIG_KEYS
      extras.uniq.each { |key| errors.add(key, :unknown_field) }
    end

    def lookup(cfg, name)
      data = cfg || {}
      raw = data[name.to_s]
      raw = data[name.to_sym] if raw.nil?
      raw
    end

    def validate_declared_field(field, cfg, errors, context)
      return unless field_visible?(field, cfg)

      raw = lookup(cfg, field.name)
      if missing?(raw, field.role)
        if field_required?(field, cfg) && !default_satisfies_required?(field)
          errors.add(field.name, :required)
        end
        return
      end

      validate_role(field, raw, errors, context)
    end

    def validate_requires(cfg, errors)
      @requires.each do |rule|
        field = find_declared(rule[:field])
        next unless field
        next unless matches_when?(rule[:when], cfg)
        next unless field_visible?(field, cfg)

        raw = lookup(cfg, field.name)
        errors.add(field.name, :required) if missing?(raw, field.role)
      end
    end

    def validate_capabilities(cfg, errors)
      if @capabilities[:transport_retry] && truthy?(value(cfg, :retryOnTransportError))
        spec = @capabilities[:transport_retry]
        idempotent = matches_when?(spec[:idempotent_when], cfg)
        present = spec[:or_present].present? && !missing?(lookup(cfg, spec[:or_present]), :literal)
        errors.add(:retryOnTransportError, :retry_not_idempotent) unless idempotent || present
      end

      if @capabilities[:timeouts]
        connect = value(cfg, :connectTimeout).to_i
        read = value(cfg, :readTimeout).to_i
        if connect.positive? && read.positive? && (connect + read) > RUN_LIMIT_SECONDS
          errors.add(:readTimeout, :timeout_exceeds_run_limit, cap: RUN_LIMIT_SECONDS)
        end
      end
    end

    def validate_role(field, raw, errors, context)
      case field.role
      when :input then validate_input(field, raw, errors)
      when :output then validate_output(field, raw, errors)
      when :expression then validate_expression(field, raw, errors)
      when :literal then validate_length(field, raw, errors)
      when :template then validate_template(field, raw, errors)
      when :enum then validate_enum(field, raw, errors)
      when :flag then validate_flag(field, raw, errors)
      when :integer then validate_integer(field, raw, errors)
      when :decimal then validate_decimal(field, raw, errors)
      when :list then validate_list(field, raw, errors, context)
      when :mapping then validate_mapping(field, raw, errors, context)
      when :conditions then validate_conditions(field, raw, errors)
      when :entity_attribute then validate_entity_attribute(field, raw, errors, context)
      when :reference then validate_reference(field, raw, errors)
      when :localized_text then validate_localized_text(field, raw, errors)
      end
    end

    def validate_input(field, raw, errors)
      parts = raw.to_s.split(".")
      unless parts.size.between?(1, 4) && parts.all? { |part| IDENT_SEGMENT.match?(part) }
        errors.add(field.name, :invalid_identifier)
        return
      end
      root = parts.first
      if INPUT_FORBIDDEN_ROOTS.include?(root) ||
          (Shared::IdentifierSanitizer::RUBY_RESERVED.include?(root) && SEEDED_KEYS.exclude?(root))
        errors.add(field.name, :reserved_name, value: root)
      end
    end

    def validate_output(field, raw, errors)
      name = raw.to_s
      unless IDENT_SEGMENT.match?(name)
        errors.add(field.name, :invalid_identifier)
        return
      end
      if Shared::IdentifierSanitizer::RUBY_RESERVED.include?(name) || OUTPUT_RESERVED.include?(name)
        errors.add(field.name, :reserved_name, value: name)
      end
    end

    def validate_expression(field, raw, errors)
      text = raw.to_s.strip
      safety = expression_safety
      unless safety.safe_expression?(text)
        errors.add(field.name, :invalid_expression)
        return
      end
      result = Prism.parse(text)
      unless result.success? && result.value.statements.body.size == 1
        errors.add(field.name, :not_one_statement)
      end
    end

    def validate_length(field, raw, errors)
      max = field.options[:max_length]
      return unless max && raw.to_s.length > max

      errors.add(field.name, :too_long, max_length: max)
    end

    def validate_template(field, raw, errors)
      Liquid::Template.parse(raw.to_s)
    rescue Liquid::Error
      errors.add(field.name, :invalid_template)
    end

    def validate_enum(field, raw, errors)
      allowed = Array(field.options[:values]).map(&:to_s)
      return if allowed.include?(raw.to_s)

      errors.add(field.name, :not_in_list, allowed: allowed.join(", "))
    end

    def validate_flag(field, raw, errors)
      return if raw == true || raw == false

      errors.add(field.name, :not_boolean)
    end

    def validate_integer(field, raw, errors)
      unless integer_like?(raw)
        errors.add(field.name, :invalid_integer)
        return
      end
      number = raw.to_i
      min = field.options[:min]
      max = field.options[:max]
      return if (min.nil? || number >= min) && (max.nil? || number <= max)

      errors.add(field.name, :out_of_range, min: min, max: max)
    end

    def validate_decimal(field, raw, errors)
      unless numeric_like?(raw)
        errors.add(field.name, :invalid_decimal)
        return
      end
      number = raw.to_f
      min = field.options[:min]
      max = field.options[:max]
      return if (min.nil? || number >= min) && (max.nil? || number <= max)

      errors.add(field.name, :out_of_range, min: min, max: max)
    end

    def validate_list(field, raw, errors, context)
      unless raw.is_a?(Array)
        errors.add(field.name, :invalid_list)
        return
      end
      item_role = field.options[:item]
      return unless item_role

      raw.each do |item|
        validate_role(proxy_field(field.name, item_role), item, errors, context)
      end
    end

    def validate_mapping(field, raw, errors, context)
      rows = raw
      unless rows.is_a?(Array) && rows.all? { |row| row.is_a?(Hash) }
        errors.add(field.name, :invalid_mapping)
        return
      end
      key_role = field.options[:key]
      value_role = field.options[:value]
      rows.each do |row|
        key = row["key"] || row[:key]
        value = row["value"] || row[:value]
        validate_role(proxy_field(field.name, key_role), key, errors, context) if key_role && !key.nil?
        validate_role(proxy_field(field.name, value_role), value, errors, context) if value_role && !value.nil?
      end
    end

    def validate_conditions(field, raw, errors)
      return if raw.is_a?(Hash)

      errors.add(field.name, :invalid_conditions)
    end

    def validate_entity_attribute(field, raw, errors, context)
      slug = raw.to_s
      unless IDENT_SEGMENT.match?(slug)
        errors.add(field.name, :invalid_identifier)
        return
      end
      entity = bound_entity_from(context, field)
      return unless entity
      return if entity_has_attribute?(entity, slug)

      errors.add(field.name, :unknown_attribute, attribute: slug, entity: entity.try(:name) || entity.to_s)
    end

    def validate_reference(field, raw, errors)
      return if raw.to_s.present?

      errors.add(field.name, :unknown_reference, source: field.options[:source])
    end

    def validate_localized_text(field, raw, errors)
      unless raw.is_a?(Hash)
        errors.add(field.name, :en_required)
        return
      end
      english = raw["en"] || raw[:en]
      errors.add(field.name, :en_required) if english.to_s.strip.empty?
    end

    def proxy_field(name, role)
      DeclaredField.new(name: name.to_s, role: role.to_sym, options: {}, conditions: [], capabilities: [])
    end

    def field_visible?(field, cfg)
      rules = []
      rules << field.options[:visible] if field.options[:visible].present?
      @requires.select { |rule| rule[:field] == field.name }.each { |rule| rules << rule[:when] }
      return true if rules.empty?

      rules.any? { |rule| matches_when?(rule, cfg) }
    end

    def field_required?(field, cfg)
      return false unless field_visible?(field, cfg)
      return true if field.options[:required]

      @requires.any? { |rule| rule[:field] == field.name && matches_when?(rule[:when], cfg) }
    end

    def default_satisfies_required?(field)
      field.options.key?(:default) && !missing?(field.options[:default], field.role)
    end

    def matches_when?(hash, cfg)
      hash.all? do |key, expected|
        actual = visibility_value(cfg, key)
        Array(expected).map(&:to_s).include?(actual.to_s)
      end
    end

    def visibility_value(cfg, name)
      field = find_declared(name)
      raw = lookup(cfg, name)
      if field.nil?
        raw
      elsif missing?(raw, field.role)
        coerce(field, field.options[:default])
      else
        coerce(field, raw)
      end
    end

    def coerce(field, raw)
      return raw if raw.nil? || field.nil?

      case field.role
      when :flag then truthy?(raw)
      when :integer then integer_like?(raw) ? raw.to_i : raw
      when :decimal then numeric_like?(raw) ? raw.to_f : raw
      when :enum, :input, :output, :expression, :literal, :template,
           :entity_attribute, :reference
        raw
      else
        raw
      end
    end

    def missing?(value, role)
      return false if role == :flag && [true, false].include?(value)
      return true if value.nil?
      return true if value == ""
      return false if %i[list mapping conditions localized_text integer decimal flag].include?(role)

      value.respond_to?(:blank?) ? value.blank? : false
    end

    def integer_like?(value)
      value.is_a?(Integer) || (value.is_a?(String) && value.strip.match?(/\A-?\d+\z/))
    end

    def numeric_like?(value)
      value.is_a?(Numeric) || (value.is_a?(String) && value.strip.match?(/\A-?\d+(\.\d+)?\z/))
    end

    def truthy?(value)
      value == true || value.to_s == "true"
    end

    def expression_safety
      @expression_safety ||= Object.new.extend(Shared::ExpressionSafety)
    end

    def bound_entity_from(context, field)
      return unless context.respond_to?(:bound_entity) || (context.is_a?(Hash) && context[:bound_entity])

      context.respond_to?(:bound_entity) ? context.bound_entity : context[:bound_entity]
    end

    def entity_has_attribute?(entity, slug)
      names = if entity.respond_to?(:attribute_slugs)
        entity.attribute_slugs
      elsif entity.respond_to?(:attributes)
        Array(entity.attributes).map { |item| item.try(:slug) || item.to_s }
      else
        []
      end
      names.map(&:to_s).include?(slug)
    end
  end
end
