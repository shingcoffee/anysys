# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        # The feature matrix, rendered from {EntityDefinitions::Capabilities}.
        #
        # Nothing here is hand-written: registering a new input control,
        # validator, group icon, computed function or extendable base model
        # makes it appear in the prompt on the next turn. Keep it that way —
        # a literal list added here is a list that will silently go stale.
        class EntityCapabilities < Section
          heads "Entity capability matrix (authoritative, generated from the live registries)"
          document "entity_capabilities"

          private

          def body
            [
              document,
              controls_table,
              rules_table,
              grouping_options,
              derived_fields,
              audiences,
              extendable_models
            ].compact.join("\n\n")
          end

          def capabilities = EntityDefinitions::Capabilities

          def controls_table
            rows = capabilities.controls.map do |control|
              "| #{control.value} | #{control.category} | #{control.label} | " \
                "#{control.config_kind || "—"} | #{control.validators.join(" ")} |"
            end
            table(
              "### Input controls (`html_type`)",
              "| html_type | category | control | config | rules allowed |",
              rows
            )
          end

          def rules_table
            rows = capabilities.validators.map do |validator|
              "| #{validator.type} | #{validator.config_example || "—"} | #{validator.controls.join(" ")} |"
            end
            table(
              "### Rules (`rules[].type`)",
              "| type | value fields | applies to |",
              rows
            )
          end

          def grouping_options
            [
              "### Attribute groups",
              "- `key` — stable identifier; attributes reference it via `group`",
              "- `icon` — one of: #{list(capabilities.group_icons)}",
              "- `color` — one of: #{list(capabilities.group_colors)}"
            ].join("\n")
          end

          def derived_fields
            [
              "### Derived fields",
              "- `kind: \"calculated\"` — `formula` over sibling `slug` values on the same entity " \
                "(e.g. `unit_price * quantity`). Stored read-only.",
              "- `kind: \"computed\"` — aggregates a related entity through its bridge. " \
                "`aggregate.function` is one of #{list(capabilities.computed_functions)}; every function except " \
                "`count` needs `aggregate.source_attribute` pointing at a numeric bridge attribute " \
                "(#{list(capabilities.numeric_control_values)}). `aggregate.precision` is 0–" \
                "#{capabilities.computed_max_precision}. An optional `aggregate.filter` uses operators " \
                "#{list(capabilities.computed_filter_operators)}."
            ].join("\n")
          end

          def audiences
            "### Audiences\n`access.visible_to`, `access.rules_apply_to` and `access.editable_by` accept the keys " \
              "#{list(capabilities.audiences)}; each defaults to `true`."
          end

          def extendable_models
            models = capabilities.extendable_models(context.customer_id)
            return "### Extendable base models\nNone are enabled for this tenant — never set `extends`." if models.empty?

            [
              "### Extendable base models\n`extends` accepts only: #{list(models)}. " \
                "Use it when the user wants to extend an existing platform record rather than start from scratch.",
              person_model_line,
              *models.map { |model| inherited_fields_line(model) }
            ].compact.join("\n")
          end

          def person_model_line
            model = capabilities.person_model(context.customer_id)
            return "- Person base model: none for this tenant — leave `extends` unset on person entities." unless model

            "- Person base model: `#{model}` — the `extends` of the one person entity of a domain, set only once " \
              "the admin confirms they sign in to see their own records. It can't be undone."
          end

          def inherited_fields_line(model)
            fields = capabilities.base_model_fields(context.customer_id, model)
            return if fields.empty?

            "- `#{model}` already holds #{list(fields)}; an entity extending it never declares those slugs."
          end

          def table(title, header, rows)
            separator = "|#{" --- |" * header.count("|").pred}"
            [title, header, separator, *rows].join("\n")
          end

          def list(values)
            Array(values).map { |value| "`#{value}`" }.join(", ")
          end
        end
      end
    end
  end
end
