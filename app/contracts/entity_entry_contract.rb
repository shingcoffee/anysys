# frozen_string_literal: true

# EntityEntryContract
#
# Reform::Form contract for validating EntityEntry data in Trailblazer Activities.
# Provides a factory method to build entity-specific contract subclasses at runtime.
#
# Integration with Trailblazer Activity:
#   1. build_contract step: contract = EntityEntryContract.build_for(entity, audience: ctx[:audience]).new(model)
#   2. validate step: contract.validate(params) - validates and syncs to model
#   3. persist step: contract.sync / contract.save - persists validated data
#
# Attribute validators honor per-audience `visibility` + `validator_apply`
# (see EntityAttributeAudience) via ActiveModel `if:` guards. A blank audience
# means "unscoped run" and applies every declared validator.
#
# @example Building a contract for an entity in Trailblazer Activity
#   def build_contract(ctx, entity:, audience:, model:, **)
#     ctx[:contract] = EntityEntryContract.build_for(entity, audience: audience).new(model)
#   end
#
#   def validate(ctx, contract:, params:, **)
#     contract.validate(params)
#   end
#
# @example Direct usage with EntityEntry
#   entity = Entity.find(1)
#   entry = EntityEntry.new(entity: entity)
#   contract = EntityEntryContract.build_for(entity, audience: "public").new(entry)
#   contract.validate(email: "test@example.com", age: 25)
#   contract.sync  # syncs validated data to entry
#
class EntityEntryContract < Reform::Form
  include ValidatorRegistry
  include EntityAttributeAudience::ContractScope

  class_attribute :reference_rules, instance_accessor: false, default: [].freeze

  class << self
    # Factory method to build an entity-specific contract subclass.
    # Creates a new subclass with properties and validations derived from
    # the entity's property_schema.
    #
    # @param entity [Entity] the entity defining the property schema
    # @param audience [String, Symbol, nil] audience the returned class validates
    #   for (`admin` / `member` / `public`). A fresh subclass is built per call,
    #   so the audience never leaks between requests. When nil, every declared
    #   validator applies (unscoped run: activity traces, console, jobs).
    # @param writable_slugs [Array<String>, nil] optional write allowlist;
    #   excluded properties keep their readers and validators.
    # @return [Class] a subclass of EntityEntryContract configured for the entity
    def build_for(entity, audience: nil, writable_slugs: nil)
      schema = entity&.property_schema_json || []
      return self if schema.empty?

      requested_audience = audience&.to_s.presence
      write_set = writable_slugs&.map(&:to_s)

      Class.new(self) do
        self.default_validation_audience = requested_audience

        schema.each { |attr| declare_schema_attribute(attr, writable_slugs: write_set) }
        declare_reference_rules(schema, writable_slugs: write_set)
      end
    end

    # Readers and validators remain intact; only the write boundary changes.
    # Shared with ContractGenerator so generated contracts have identical flags.
    def schema_property_options(attr, writable_slugs: nil)
      slug = attr["name_slug"].to_s
      reserved = EntityEntry.reserved_attribute_slug?(slug)
      derived = %w[Calculated Computed].include?(attr["type"]) || attr["storage"] == "computed"
      excluded = writable_slugs && !writable_slugs.include?(slug)
      # Reform 2.6 uses :writeable for model sync and :parse for deserialization.
      reserved || derived || excluded ? { writeable: false, parse: false } : {}
    end

    # Declares a Reform property with optional validations.
    # Used for manual contract configuration via class_eval.
    #
    # @param name [Symbol] property name
    # @param validates [Hash] validation options passed to `validates`
    def property_accessor(name, validates: nil, **property_options)
      property name, **property_options
      self.validates name, **validates if validates.present?
    end

    private

    # Declares one property_schema entry as a property plus its audience-scoped
    # validations. Validators disabled for every audience are never declared.
    #
    # @param attr [Hash] one property_schema entry
    def declare_schema_attribute(attr, writable_slugs: nil)
      slug = attr["name_slug"].presence&.to_sym
      return unless slug

      property slug, **schema_property_options(attr, writable_slugs: writable_slugs)

      options = build_validation_options(attr["validators"] || [])
      return if options.blank?

      audiences = EntityAttributeAudience.applying_audiences(attr)
      return if audiences.empty?
      return validates slug, **options if EntityAttributeAudience.every_audience?(audiences)

      validates slug, **options, if: EntityAttributeAudience.contract_guard(audiences)
    end

    # Builds merged validation options from a raw validator array.
    #
    # @param raw_validators [Array<Hash>] validator list with "type" and optional "config"
    # @return [Hash] merged validation options for Rails validates
    def build_validation_options(raw_validators)
      return {} if raw_validators.empty?

      options = raw_validators.each_with_object({}) do |entry, merged|
        validator_key, config = normalize_validator(entry)
        next unless validator_key

        validator_proc = ValidatorRegistry::VALIDATORS[validator_key]
        next unless validator_proc

        validator_options = invoke_validator_proc(validator_proc, validator_key, config)
        deep_merge_options!(merged, validator_options)
      end
      allow_blank_values(options)
    end

    # Only presence makes a field required; every other check applies to a
    # submitted value, so an optional field may stay blank.
    def allow_blank_values(options)
      options.to_h do |key, value|
        next [key, value] if ValidatorRegistry::REQUIRING_VALIDATIONS.include?(key)

        [key, (value.is_a?(Hash) ? value : {}).merge(allow_blank: true)]
      end
    end

    # Normalizes a validator entry into [Symbol, Hash|nil].
    def normalize_validator(entry)
      return unless entry.is_a?(Hash)

      type = entry["type"]&.to_sym
      [type, entry["config"]]
    end

    # Invokes a validator proc, passing config values when available.
    def invoke_validator_proc(proc, key, config)
      return proc.call unless config

      case key
      when :length_in_range
        min = config["min"].to_i
        max = config["max"].to_i
        proc.call(min..max)
      when :length_minimum, :length_maximum
        proc.call(config["value"].to_i)
      when :greater_than_or_equal_to, :less_than_or_equal_to, :equal_to, :not_equal_to,
           :greater_than, :less_than
        proc.call(config["value"].to_f)
      when :format_custom
        pattern = config["pattern"].to_s
        { format: { with: Regexp.new(pattern) } }
      when :inclusion, :exclusion
        values = config["values"]
        values = values.split("\n").map(&:strip).reject(&:blank?) if values.is_a?(String)
        proc.call(Array(values))
      else
        proc.call
      end
    end

    # Deep merges validation options, combining nested hashes (e.g. multiple
    # numericality constraints). Delegates to ActiveSupport's Hash#deep_merge!.
    #
    # @param target [Hash] target hash to merge into (mutated in place)
    # @param source [Hash] source hash to merge from
    def deep_merge_options!(target, source)
      target.deep_merge!(source)
    end

    # One rule per writable entity_entries attribute; #validate_reference_targets
    # checks them all in one pass.
    def declare_reference_rules(schema, writable_slugs:)
      rules = schema.filter_map do |attr|
        entity_id = Entities::BridgeParticipants.referenced_entity_id(attr)
        next unless entity_id

        slug = attr["name_slug"].to_s
        next if slug.empty? || EntityEntry.reserved_attribute_slug?(slug) || (writable_slugs && !writable_slugs.include?(slug))

        { slug: slug, entity_id: entity_id,
          label: attr["display_label"].presence || attr["name"].presence || slug }
      end
      return if rules.empty?

      self.reference_rules = rules.freeze
      validate :validate_reference_targets
    end
  end

  private

  # A reference holds record ids of the target entity in the entry's own
  # customer. A persisted entry may keep an unchanged value whose record is
  # gone, so editing other fields never locks it.
  def validate_reference_targets
    self.class.reference_rules.each do |rule|
      values = reference_target_values(public_send(rule[:slug]))
      next if values.empty? || reference_target_unchanged?(rule[:slug], values)
      next if reference_targets_found?(rule[:entity_id], values)

      errors.add(:base, I18n.t("common.errors.dynamic.association_target_missing", field: rule[:label]))
    end
  end

  def reference_target_values(raw)
    Array(raw).map { |value| value.to_s.strip }.reject(&:empty?)
  end

  def reference_target_unchanged?(slug, values)
    model.respond_to?(:persisted?) && model.persisted? && model.respond_to?(slug) &&
      reference_target_values(model.public_send(slug)) == values
  end

  def reference_targets_found?(entity_id, values)
    ids = values.uniq
    return false unless ids.all? { |value| value.match?(/\A\d+\z/) }

    EntityEntry.where(customer_id: model.customer_id, entity_id: entity_id, id: ids).count == ids.size
  end
end
