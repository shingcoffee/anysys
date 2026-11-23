# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Utility
        class I18nTranslateGenerator < BaseGenerator
          generator_metadata do
            description "Looks up a catalog translation key with I18n.t and stores the string on " \
                        "resultVar (default translated). Use this for flash copy, email subjects, and " \
                        "pluralised labels that live in locale files; use template_render (Liquid) to " \
                        "compose a freeform body, and a template field on send_email for a single " \
                        "interpolated string. key is required (greeting.hello). locale or localeFrom " \
                        "selects the language; blank uses the request locale. interpolations bind " \
                        "ctx paths into %{name} tokens. default / fallbackLocale cover a missing key; " \
                        "raiseOnMissing fails as i18n_translate.failed."
            category :utility
            version "1.4.0"
            presentation icon: "M3 5h12M9 3v2m1.048 9.5A18.022 18.022 0 016.412 9m6.088 9h7M11 21l5-10 5 10M12.751 5C11.783 10.77 8.07 15.61 3 18.129",
                         color: "blue", single_use: false, privileged: false
          end

          config_schema do
            literal :key, required: true, example: "greeting.hello", placeholder: true,
                    description: "I18n key to look up, such as greeting.hello or notifications.new_order. " \
                                 "Required. Dot notation; do not include a locale prefix."
            literal :locale, placeholder: true,
                    description: "Locale id such as en or zh-CN. Leave blank for the request locale. " \
                                 "Ignored when localeFrom is set."
            input :localeFrom, placeholder: true, group: :advanced,
                  description: "Ctx path of a locale that overrides Locale, such as visitor_locale. " \
                               "Leave blank to use the Locale literal or the request locale."
            literal :fallbackLocale, placeholder: true,
                    description: "Locale tried when the primary lookup is missing, such as en. Leave " \
                                 "blank to skip a second lookup."
            mapping :interpolations, key: :literal, value: :literal, default: [],
                    description: "Values for %{name} tokens. Each key is an interpolation name (name, count); " \
                                 "each value is a ctx path (person.name) or a literal."
            literal :scope, placeholder: true,
                    description: "Optional I18n scope prepended to key, such as activerecord.models. " \
                                 "Leave blank when key is already fully qualified."
            literal :default, placeholder: true,
                    description: "Fallback text when the key is missing and raiseOnMissing is false, " \
                                 "such as Hello. Leave blank to let I18n emit its missing-translation string."
            input :count, placeholder: true,
                  description: "Ctx path of the pluralisation count, such as items_count. Leave blank " \
                               "when the translation has no one/other forms."
            flag :raiseOnMissing, default: false,
                 description: "When true, fail the step as i18n_translate.failed if the key (and fallback) " \
                              "are missing. Default false."
            output :resultVar, default: "translated",
                   description: "Ctx variable that receives the translated string. Default translated."
          end

          def generate_body
            attempt('"i18n_translate.failed"', FlowchartRuntime::Translate::Error) do
              [
                assign(:resultVar, "FlowchartRuntime::Translate.call(#{translate_args})"),
                "true"
              ]
            end
          end

          private

          def translate_args
            [
              read(:key),
              ("locale: #{locale_arg}" unless locale_arg == "nil"),
              ("fallback_locale: #{read(:fallbackLocale)}" if value(:fallbackLocale).to_s.strip.present?),
              ("interpolations: #{interpolations_hash}" unless interpolations_hash == "{}"),
              ("scope: #{read(:scope)}" if value(:scope).to_s.strip.present?),
              ("default: #{read(:default)}" if value(:default).to_s.strip.present?),
              ("count: #{read(:count)}" if value(:count).to_s.strip.present?),
              ("raise_on_missing: #{read(:raiseOnMissing)}" if value(:raiseOnMissing))
            ].compact.join(", ")
          end

          def interpolations_hash
            pairs = mapping_rows(:interpolations).filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              next unless key.to_s.match?(/\A[a-z_][a-zA-Z0-9_]*\z/)

              "#{key}: #{argument_expression(row['value'] || row[:value])}"
            end
            "{#{pairs.join(', ')}}"
          end

          def mapping_rows(name)
            raw = value(name)
            case raw
            when Hash then raw.map { |key, val| { "key" => key.to_s, "value" => val } }
            when Array then raw
            else []
            end
          end

          def argument_expression(raw)
            return "nil" if raw.nil?
            return raw.inspect if raw == true || raw == false || raw.is_a?(Numeric)

            src = raw.to_s
            return input_path(src.delete_prefix("ctx.")) if src.start_with?("ctx.")
            return src if src.match?(/\Actx\[:[a-zA-Z_][a-zA-Z0-9_]*\]\z/)
            return input_path(src) if src.match?(/\A[a-z_][a-zA-Z0-9_]*(?:\.[a-zA-Z0-9_]+)*\z/)

            src.inspect
          end

          def locale_arg
            value(:localeFrom).to_s.strip.empty? ? optional_literal(:locale) : read(:localeFrom)
          end

          def optional_literal(name)
            raw = value(name)
            raw.to_s.strip.empty? ? "nil" : read(name)
          end

          def input_path(path)
            root, *rest = path.to_s.split(".", -1)
            return "nil" if root.to_s.empty?
            return "ctx[:#{root}]" if rest.empty? && safe_ident?(root)

            keys = rest.map { |segment| segment.match?(/\A\d+\z/) ? segment : ":#{segment}" }.join(", ")
            "FlowchartRuntime::Step.dig(ctx[:#{root}], #{keys})"
          end
        end
      end
    end
  end
end
