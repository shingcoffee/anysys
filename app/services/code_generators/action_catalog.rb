# frozen_string_literal: true

require "digest"
require "json"

module CodeGenerators
  # Server-side step-action catalog. Reverses the JS → Ruby mirror: the editor
  # mounts this export as `data-property-editor-action-catalog-value`.
  class ActionCatalog
    CATEGORY_ORDER = %w[
      model validation data workflow finance communication security background
      file caching concurrency resilience scheduling payments outcome
      service utility
    ].freeze

    CATEGORY_FROM_METADATA = {
      "model_operations" => "model",
      "data_operations" => "data",
      "file_operations" => "file",
      "scheduling_time" => "scheduling",
      "service_invocation" => "service"
    }.freeze

    SAMPLE_KEYS = %w[
      find_model api_call assign_value send_template_email query_models
    ].freeze

    class << self
      def export(locale:)
        locale = locale.to_s
        actions = canonical_generators.map { |generator| export_generator(generator, locale: locale) }
        assemble(actions, locale: locale)
      end

      def sample_export(locale: "en")
        locale = locale.to_s
        actions = [export_generator(Phase3FixtureGenerator, locale: locale)]
        by_key = export(locale: locale)["actions"].index_by { |action| action["key"] }
        SAMPLE_KEYS.each do |key|
          action = by_key[key]
          actions << action if action
        end
        assemble(actions, locale: locale)
      end

      def export_generator(generator, locale:)
        raise ArgumentError, "#{generator.name} declares no config_schema" unless generator._config_schema

        export_declared(generator, locale: locale.to_s)
      end

      private

      def canonical_generators
        GeneratorRegistry.step_action_generators.values.uniq.sort_by(&:generator_name)
      end

      def export_declared(generator, locale:)
        key = generator.generator_name
        schema = generator._config_schema
        meta = generator._metadata || {}
        presentation = meta[:presentation] || {}
        category = normalize_category(meta[:category])
        {
          "key" => key,
          "category" => category,
          "label" => action_text(key, "label", locale: locale) || key,
          "description" => action_text(key, "description", locale: locale).to_s,
          "icon" => presentation[:icon],
          "color" => presentation[:color],
          "singleUse" => presentation[:single_use] == true,
          "privileged" => presentation[:privileged] == true,
          "fields" => schema.fields.map { |field| FieldPresenter.from_declared(key, field, locale: locale) },
          "capabilities" => capabilities_from(schema.capabilities)
        }
      end

      def assemble(actions, locale:)
        ordered = actions.sort_by do |action|
          [CATEGORY_ORDER.index(action["category"]) || 99, action["key"]]
        end
        used = ordered.map { |action| action["category"] }.uniq.sort_by { |key| CATEGORY_ORDER.index(key) || 99 }
        catalog = {
          "locale" => locale,
          "categories" => used.map { |key| { "key" => key, "label" => category_label(key, locale: locale) } },
          "actions" => ordered
        }
        catalog["digest"] = digest_for(catalog)
        catalog
      end

      def digest_for(catalog)
        payload = {
          "categories" => catalog["categories"].map { |category| { "key" => category["key"] } },
          "actions" => catalog["actions"].map { |action| digest_action(action) }
        }
        Digest::SHA256.hexdigest(JSON.generate(payload))
      end

      def digest_action(action)
        {
          "key" => action["key"],
          "category" => action["category"],
          "icon" => action["icon"],
          "color" => action["color"],
          "singleUse" => action["singleUse"],
          "privileged" => action["privileged"],
          "fields" => action["fields"].map { |field| digest_field(field) },
          "capabilities" => action["capabilities"]
        }
      end

      def digest_field(field)
        field.slice(
          "name", "role", "control", "default", "required", "group", "min", "max",
          "visibleWhen", "requiredWhen", "variablePicker", "source", "itemRole",
          "keyRole", "valueRole", "multiline", "maxLength"
        ).merge("options" => Array(field["options"]).map { |option| option["value"] })
      end

      def normalize_category(value)
        token = value.to_s
        CATEGORY_FROM_METADATA[token] || token.presence || "utility"
      end

      def category_label(key, locale:)
        i18n_key = "flowchart_actions.categories.#{key}"
        return I18n.t(i18n_key, locale: locale) if I18n.exists?(i18n_key, locale, fallback: false)

        key
      end

      def action_text(key, part, locale:)
        i18n_key = "flowchart_actions.#{key}.#{part}"
        I18n.t(i18n_key, locale: locale) if I18n.exists?(i18n_key, locale, fallback: false)
      end

      def capabilities_from(raw)
        retry_spec = raw[:transport_retry]
        timeouts = raw[:timeouts]
        {
          "transportRetry" => retry_spec && {
            "idempotentWhen" => stringify_when(retry_spec[:idempotent_when]),
            "orPresent" => retry_spec[:or_present],
            "maxAttempts" => 2
          },
          "timeouts" => timeouts && {
            "open" => timeouts[:open],
            "read" => timeouts[:read],
            "cap" => timeouts[:cap]
          },
          "circuitBreaker" => raw[:circuit_breaker] == true
        }
      end

      def stringify_when(hash)
        (hash || {}).each_with_object({}) { |(key, value), result| result[key.to_s] = value }
      end
    end
  end
end
