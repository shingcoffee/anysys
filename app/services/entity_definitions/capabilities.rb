# frozen_string_literal: true

module EntityDefinitions
  # Runtime inventory of everything an entity definition can express.
  #
  # Every list is derived from the app's own registries rather than restated
  # here, so adding a new html type, validator, group icon, computed function
  # or extendable model automatically reaches both the assistant prompt and the
  # JSON Schema the LLM is held to. Nothing in this class may be hand-maintained
  # in parallel with a registry.
  #
  #   HtmlTypeOptions            → input controls, their category, their config kind
  #   ValidatorRegistry          → validators, their config shape, per-control allow-list
  #   EntityAttributeGroupOptions→ attribute-group icons and colors
  #   Entities::ComputedCompiler → aggregate functions, filter operators, precision
  #   ExtendableModelRegistry    → base models this tenant may extend
  #
  # Labels are stable English derived from registry keys, never I18n, because
  # the prompt is a machine contract and must not change with the admin locale.
  class Capabilities
    Control = Struct.new(:value, :category, :label, :config_kind, :validators, keyword_init: true)
    Validator = Struct.new(:type, :config_kind, :config_example, :controls, keyword_init: true)

    # Config payload each validator key expects under `config`. Keys without an
    # entry take no config. Mirrors ValidatorRegistry::VALIDATOR_CONFIG_TYPES.
    VALIDATOR_CONFIG_EXAMPLES = {
      "single_value" => %({"value": 10}),
      "range" => %({"min": 1, "max": 255}),
      "pattern" => %({"pattern": "\\\\A[A-Z]{2}\\\\d{4}\\\\z"}),
      "list" => %({"values": ["Draft", "Active"]})
    }.freeze

    # Attribute `type` values the assistant may author. EntityReference is
    # excluded on purpose: it is system-owned on auto-created bridge entities.
    AUTHORABLE_ATTRIBUTE_TYPES = %w[Calculated Computed].freeze

    # Value of `config.options_source` that binds a choice list to another
    # entity's live entries instead of a static list.
    ENTITY_ENTRIES_OPTIONS_SOURCE = "entity_entries"

    # The base model a person-like entity (Student, Patient, Volunteer, …)
    # extends. A create_entity call may extend it at most once, and that
    # entity is the primary one of the call.
    PERSON_MODEL = "Authentication::User"

    class << self
      # @return [Array<Control>] every input control, in registry order.
      def controls
        HtmlTypeOptions::GROUPED_HTML_TYPES.flat_map do |category, entries|
          entries.map do |label_key, value|
            Control.new(
              value: value,
              category: humanize(category),
              label: humanize(label_key),
              config_kind: HtmlTypeOptions.config_type_for(value)&.to_s,
              validators: ValidatorRegistry::HTML_TYPE_VALIDATORS.fetch(value, [])
            )
          end
        end
      end

      def control_values
        controls.map(&:value)
      end

      # Controls whose `config.options` list is mandatory.
      def selection_control_values
        HtmlTypeOptions::SELECTION_TYPES
      end

      # @return [Array<Validator>] every validator, with the controls it suits.
      def validators
        by_control = ValidatorRegistry::HTML_TYPE_VALIDATORS.each_with_object(
          Hash.new { |hash, key| hash[key] = [] }
        ) do |(control, keys), acc|
          next unless control_values.include?(control)

          keys.each { |key| acc[key] << control }
        end

        validator_types.map do |type|
          kind = ValidatorRegistry::VALIDATOR_CONFIG_TYPES[type]
          Validator.new(
            type: type,
            config_kind: kind,
            config_example: kind && VALIDATOR_CONFIG_EXAMPLES[kind],
            controls: by_control[type]
          )
        end
      end

      def validator_types
        ValidatorRegistry::VALIDATOR_LABELS.keys
      end

      def group_icons
        EntityAttributeGroupOptions::ICONS.keys
      end

      def group_colors
        EntityAttributeGroupOptions::COLORS
      end

      def computed_functions
        Entities::ComputedCompiler::FUNCTIONS
      end

      def computed_filter_operators
        Entities::ComputedCompiler::FILTER_OPS
      end

      def computed_max_precision
        Entities::ComputedCompiler::MAX_PRECISION
      end

      # Controls a Computed sum/avg/min/max may aggregate over.
      def numeric_control_values
        Entities::ComputedCompiler::NUMERIC_HTML_TYPES
      end

      def audiences
        EntityAttributeAudience::AUDIENCES
      end

      # Tenant-specific: the base models this customer is allowed to extend.
      # @return [Array<String>] class names, empty when nothing is extendable.
      def extendable_models(customer_id)
        ExtendableModelRegistry.for_customer(customer_id).map { |model| model[:class_name] }
      end

      # @return [String, nil] PERSON_MODEL when this tenant may extend it.
      def person_model(customer_id)
        PERSON_MODEL if extendable_models(customer_id).include?(PERSON_MODEL)
      end

      # Column names an extension of `class_name` inherits, so it may not
      # redeclare them as attributes. Empty unless the tenant may extend it.
      # @return [Array<String>]
      def base_model_fields(customer_id, class_name)
        return [] unless extendable_models(customer_id).include?(class_name.to_s)

        klass = class_name.to_s.safe_constantize
        return [] unless klass.is_a?(Class) && klass < ApplicationRecord

        klass.column_names & ExtendableModelRegistry.selected_attributes(customer_id, class_name)
      end

      private

      def humanize(key)
        key.to_s.tr("_", " ").capitalize
      end
    end
  end
end
