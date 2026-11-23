# frozen_string_literal: true

require "digest"
require "json"

module CodeGenerators
  # Server-side element + connection catalog. The editor embeds this export once
  # on the canvas root as `data-flowchart-canvas-element-catalog-value`.
  class ElementCatalog
    TYPE_ORDER = %w[start end process decision loop subflow].freeze
    I18N_PREFIX = "flowchart_elements"
    NOTES_KEY = "description"

    class << self
      def export(locale:)
        locale = locale.to_s
        types = TYPE_ORDER.each_with_object({}) do |type, acc|
          acc[type] = export_type(type, locale: locale)
        end
        catalog = {
          "locale" => locale,
          "types" => types,
          "connection" => {
            "fields" => ConnectionSchema.schema.fields.map do |field|
              row = ActionCatalog::FieldPresenter.from_declared(
                "connection", field, locale: locale, i18n_prefix: I18N_PREFIX
              )
              row["name"] == NOTES_KEY ? row.merge("label" => notes_label(locale)) : row
            end
          },
          "operators" => ConditionOperators.export(locale: locale),
          "chrome" => chrome(locale)
        }
        catalog["digest"] = digest_for(catalog)
        catalog
      end

      private

      def export_type(type, locale:)
        fields = fields_for(type, locale: locale)
        {
          "type" => type,
          "label" => type_text(type, "label", locale: locale),
          "defaultLabel" => type_text(type, "defaultLabel", locale: locale),
          "tabs" => tabs_for(type, fields),
          "fields" => fields
        }
      end

      def fields_for(type, locale:)
        return [] if type == "process"

        generator = GeneratorRegistry.find_element_type(type)
        raise ArgumentError, "unknown element type #{type}" unless generator
        raise ArgumentError, "#{generator.name} declares no config_schema" unless generator._config_schema

        generator._config_schema.fields.map do |field|
          ActionCatalog::FieldPresenter.from_declared(
            type, field, locale: locale, i18n_prefix: I18N_PREFIX
          )
        end
      end

      def tabs_for(type, fields)
        tabs = ["general"]
        tabs << "steps" if type == "process"
        tabs << "branches" if type == "decision"
        tabs << "io"
        tabs << "advanced" if fields.any? { |field| field["group"] == "advanced" }
        tabs
      end

      def chrome(locale)
        {
          "label" => { "label" => chrome_text("label", locale: locale) },
          "notes" => { "key" => NOTES_KEY, "label" => notes_label(locale) }
        }
      end

      def type_text(type, part, locale:)
        I18n.t("#{I18N_PREFIX}.#{type}.#{part}", locale: locale)
      end

      def chrome_text(name, locale:)
        I18n.t("#{I18N_PREFIX}.chrome.#{name}.label", locale: locale)
      end

      def notes_label(locale)
        I18n.t("common.labels.notes", locale: locale)
      end

      def digest_for(catalog)
        payload = {
          "types" => catalog["types"].transform_values { |row| digest_type(row) },
          "connection" => {
            "fields" => catalog["connection"]["fields"].map { |field| digest_field(field) }
          },
          "operators" => catalog["operators"].map { |operator| operator["value"] }
        }
        Digest::SHA256.hexdigest(JSON.generate(payload))
      end

      def digest_type(row)
        {
          "type" => row["type"],
          "tabs" => row["tabs"],
          "fields" => row["fields"].map { |field| digest_field(field) }
        }
      end

      def digest_field(field)
        field.slice(
          "name", "role", "control", "default", "required", "group", "min", "max",
          "visibleWhen", "requiredWhen", "variablePicker", "source", "itemRole",
          "keyRole", "valueRole", "multiline", "maxLength"
        ).merge("options" => Array(field["options"]).map { |option| option["value"] })
      end
    end
  end
end
