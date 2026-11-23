# frozen_string_literal: true

module FlowchartDefinitions
  module Assistant
    # Builds the assistant flowchart palette from ActionCatalog so the prompt
    # cannot drift from the ported generator schemas. Action summaries and
    # field descriptions are the generators' model-facing documentation
    # (`generator_metadata description` and each field's `description:`).
    class SchemaGenerator
      PALETTE_PATH = Rails.root.join("app/services/flowchart_definitions/structure_schema.palette.json")
      LOCALE = "en"
      # The palette documents every field of every action, so it is sized for
      # the flowchart system prompt rather than for one tool schema.
      PROMPT_PALETTE_BUDGET = 220_000
      CAPABILITY_ORDER = %w[timeouts transport_retry circuit_breaker].freeze

      LEGEND = <<~TEXT.strip
        How to read the palette. Each action starts with `action_key (Label): summary`. Each field line is
        `name role[=default][!] [a|b*|c] [when key=value] - description`:
        ! = required; a|b*|c = allowed values, * marks the default; `when key=value` = the field applies only
        when that other field has that value (omit it otherwise). No default means blank; flags default to false.
        Field roles (the value each role takes in config):
        - input: a ctx path without the ctx. prefix, dot separated, up to 4 segments (model.email, params.id,
          cart_lines). A record path reads its stored, calculated and rolled-up values.
        - output: a ctx variable name (snake_case) the step writes; later steps read it as ctx[:name] or by path.
          Reusing a name (such as model) replaces its value. Never a run key the page seeds (params, bound_entity,
          customer_id, current_user_id, current_user_role, audience, locale, request_ip, user_agent, ...) and
          never errors, error_details, result or submission_outcome.
        - expression: one Ruby expression over ctx, such as ctx[:model].total.to_f * 1.1, "Order " +
          ctx[:model].number.to_s, Date.current or 3.days.from_now. Use .to_f / .to_i in arithmetic.
        - literal: plain text taken exactly as written (a key, a name, a number written as text).
        - template: text with Liquid placeholders over ctx paths, such as "Hi {{ model.name }}".
        - enum: exactly one of the listed values. flag: true or false. integer / decimal: a number within its range.
        - list: a JSON array of the item role (list[entity_attribute] = attribute slugs).
        - mapping: a JSON array of {"key": ..., "value": ...} rows; mapping[k->v] names the key and value roles.
        - conditions: {"type":"group","joins":["AND"|"OR" one per gap],"conditions":[{"kind":"field","leftOperand":
          ...,"operator":...,"rightOperand":...}]}. In record queries leftOperand is an attribute slug of the
          queried entity; elsewhere it is a ctx path written ctx.model.status. rightOperand is a literal or a
          ctx path. Operators: == != > >= < <= contains starts_with ends_with matches_regex in_range is_type
          (binary); is_true is_false is_empty is_not_empty is_nil (no rightOperand).
        - entity_attribute: an attribute slug (name_slug) of the record's entity, as in the entity catalog.
        - reference: the id or key of an existing item the server resolves (flowchart id, email or SMS template
          id, constant id, page action key, job or service class name).
        - localized_text: {"en": "...", "zh-CN": "..."}; en is required, zh-CN recommended.
        Capabilities (shared advanced fields, listed as `+ name` under an action; leave them at their defaults
        unless the user asks):
        - timeouts: connectTimeout (1-5 s) and readTimeout (1-9 s); together at most 10 s.
        - transport_retry: retryOnTransportError + retryAttempts (1-2); only for requests that cannot act twice.
        - circuit_breaker: circuitBreaker + breakerName + failureThreshold + resetTimeoutSeconds; fail fast after
          repeated failures of the same remote service.
      TEXT

      class << self
        def catalog(locale: LOCALE)
          locale = locale.to_s
          catalogs[locale] ||= CodeGenerators::ActionCatalog.export(locale: locale)
        end

        def palette_document(locale: LOCALE)
          source = catalog(locale: locale)
          {
            "categories" => compact_categories(source),
            "step_actions" => source.fetch("actions").map { |action| compact_action(action) },
            "element_types" => compact_elements,
            "connection" => compact_connection
          }
        end

        def palette_json(locale: LOCALE)
          "#{JSON.pretty_generate(palette_document(locale: locale))}\n"
        end

        # Line-format catalog the LLM reads: every action with its summary and
        # every field with its role, default, applicability and description.
        def prompt_palette(locale: LOCALE)
          document = palette_document(locale: locale)
          actions = document.fetch("step_actions").index_by { |action| action["action"] }
          lines = [LEGEND, ""]
          document.fetch("categories").each do |category|
            names = Array(category["actions"]).select { |name| actions.key?(name) }
            next if names.empty?

            lines << "## #{category["label"]}"
            names.each { |name| lines.concat(action_lines(actions.delete(name))) }
          end
          actions.each_value { |action| lines.concat(action_lines(action)) }
          lines << ""
          lines << "## Structural elements"
          document.fetch("element_types").each { |element| lines.concat(element_lines(element)) }
          lines.concat(connection_lines(document.fetch("connection")))
          lines.join("\n")
        end

        def write!(locale: LOCALE)
          File.write(PALETTE_PATH, palette_json(locale: locale))
          PALETTE_PATH
        end

        def action_index(locale: LOCALE)
          indexes[locale.to_s] ||= catalog(locale: locale).fetch("actions").index_by { |action| action["key"] }
        end

        def action_row(name, locale: LOCALE)
          action_index(locale: locale)[name.to_s]
        end

        def canonical_keys(locale: LOCALE)
          catalog(locale: locale).fetch("actions").map { |action| action["key"] }
        end

        def reset!
          @catalogs = nil
          @indexes = nil
        end

        private

        def catalogs
          @catalogs ||= {}
        end

        def indexes
          @indexes ||= {}
        end

        def compact_categories(source)
          grouped = source.fetch("actions").group_by { |action| action["category"] }
          source.fetch("categories").map do |category|
            rows = grouped[category["key"]] || []
            {
              "key" => category["key"],
              "label" => category["label"],
              "action_count" => rows.size,
              "actions" => rows.map { |action| action["key"] }
            }
          end
        end

        def compact_action(action)
          generator = CodeGenerators::GeneratorRegistry.find_step_action(action["key"])
          fields = Array(action["fields"]).map { |field| compact_field(field, declared_field(generator, field["name"])) }
          row = {
            "action" => action["key"],
            "label" => action["label"],
            "category" => action["category"],
            "description" => summary_for(generator, action["description"]),
            "config_fields" => fields,
            "inputs" => fields.filter_map { |field| field["name"] if %w[input expression].include?(field["role"]) },
            "outputs" => fields.filter_map { |field| field["name"] if field["role"] == "output" }
          }
          row.delete("inputs") if row["inputs"].empty?
          row.delete("outputs") if row["outputs"].empty?
          row
        end

        def summary_for(generator, fallback)
          generator&._metadata&.dig(:description).to_s.strip.presence || fallback.to_s
        end

        def declared_field(generator, name)
          generator&._config_schema&.find_declared(name)
        end

        def compact_field(field, declared)
          options = Array(field["options"]).filter_map { |option|
            option.is_a?(Hash) ? option["value"].presence : option.presence
          }
          compact = {
            "name" => field["name"],
            "role" => field["role"],
            "description" => declared&.options&.dig(:description),
            "required" => field["required"] == true,
            "default" => field["default"],
            "options" => options,
            "visibleWhen" => field["visibleWhen"],
            "requiredWhen" => field["requiredWhen"],
            "min" => field["min"],
            "max" => field["max"],
            "itemRole" => field["itemRole"],
            "keyRole" => field["keyRole"],
            "valueRole" => field["valueRole"],
            "capability" => Array(declared&.capabilities).first&.to_s
          }
          compact.delete("required") unless compact["required"]
          compact.delete("options") if options.empty?
          %w[description default visibleWhen requiredWhen min max itemRole keyRole valueRole capability].each do |key|
            compact.delete(key) if compact[key].nil?
          end
          compact
        end

        def action_lines(action)
          fields = Array(action["config_fields"])
          own, shared = fields.partition { |field| field["capability"].nil? }
          lines = ["#{action["action"]} (#{action["label"]}): #{action["description"]}"]
          lines.concat(own.map { |field| "  #{field_line(field)}" })
          lines << "  #{capability_line(shared)}" if shared.any?
          lines
        end

        def capability_line(fields)
          names = fields.map { |field| field["capability"] }.uniq.sort_by { |name| CAPABILITY_ORDER.index(name) || 99 }
          timeouts = fields.select { |field| field["capability"] == "timeouts" }
          parts = names.map do |name|
            next name unless name == "timeouts" && timeouts.any?

            "timeouts(#{timeouts.map { |field| "#{field["name"]}=#{field["default"]}" }.join(", ")})"
          end
          "+ #{parts.join(", ")}"
        end

        def field_line(field)
          options = Array(field["options"]).reject(&:blank?)
          default = field["default"]
          marked = field.key?("default") && options.include?(default)
          role = role_token(field)
          role += "=#{short_default(default)}" if field.key?("default") && !marked && !implied_default?(field["role"], default)
          role += "!" if field["required"]
          parts = [field["name"], role]
          parts << options.map { |option| option == default && marked ? "#{option}*" : option }.join("|") if options.any?
          parts << "min=#{field["min"]}" unless field["min"].nil?
          parts << "max=#{field["max"]}" unless field["max"].nil?
          parts << applies_when(field) if applies_when(field)
          line = parts.join(" ")
          field["description"].present? ? "#{line} - #{field["description"]}" : line
        end

        def role_token(field)
          role = field["role"].to_s
          case role
          when "list" then field["itemRole"] ? "list[#{field["itemRole"]}]" : role
          when "mapping"
            field["keyRole"] || field["valueRole"] ? "mapping[#{field["keyRole"] || "text"}->#{field["valueRole"] || "text"}]" : role
          else role
          end
        end

        def applies_when(field)
          rule = field["visibleWhen"] || field["requiredWhen"]
          return if rule.blank?

          "when #{rule.map { |key, value| "#{key}=#{Array(value).join("|")}" }.join(" and ")}"
        end

        def short_default(value)
          case value
          when Hash, Array
            value.empty? ? value.to_json : "{…}"
          when /\A[\w.\/:-]+\z/
            value
          else
            value.inspect
          end
        end

        def implied_default?(role, default)
          default.nil? || default == "" || (role == "flag" && default == false) ||
            (%w[list mapping].include?(role) && default == []) ||
            (role == "conditions" && default.is_a?(Hash) && Array(default["conditions"]).empty?)
        end

        def compact_elements
          Palette::ELEMENT_DOCS.map do |doc|
            generator = CodeGenerators::GeneratorRegistry.find_element_type(doc["type"])
            fields = UiConfigSchema.element_fields_for(doc["type"])
            next doc if fields.empty?

            doc.merge("config_fields" => fields.map { |field| compact_field(field, declared_field(generator, field["name"])) })
          end
        end

        def element_lines(element)
          ["#{element["type"]}: #{element["description"]}",
           *Array(element["config_fields"]).map { |field| "  #{field_line(field)}" }]
        end

        def compact_connection
          schema = CodeGenerators::ConnectionSchema.schema
          fields = schema.fields.map do |declared|
            row = CodeGenerators::ActionCatalog::FieldPresenter.from_declared(
              "connection", declared, locale: LOCALE, i18n_prefix: "flowchart_elements"
            )
            compact_field(row, declared)
          end
          { "description" => Palette::CONNECTION_DOC, "config_fields" => fields }
        end

        def connection_lines(connection)
          ["connection: #{connection["description"]}",
           *Array(connection["config_fields"]).map { |field| "  #{field_line(field)}" }]
        end
      end
    end
  end
end
