# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Outcome
        class HandOffToModuleGenerator < BaseGenerator
          INPUT_NAME = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/
          EXIT_KINDS = %w[none page url route].freeze

          generator_metadata do
            description "Sends the visitor to a FeatureModules handoff after the submission saves, parking { module_key, input, exit_target } on ctx[:submission_outcome] handoff. Use request_payment for a payment checkout (it is the payment-specific handoff). Use set_submission_outcome for flash copy; it preserves an existing handoff. Reads moduleKey and input expressions. Does not create the module's records here. Refuses hand_off_to_module.module_unavailable when the module is off or has no handoff for this customer."
            category :outcome
            version "1.2.0"
            presentation icon: "M13 7l5 5m0 0l-5 5m5-5H6",
                        color: "teal", single_use: false, privileged: false
          end

          config_schema do
            literal :moduleKey, required: true, placeholder: true, example: "payment",
                    description: "Key of a handoff-enabled module this customer has turned on, such as payment. Checked at run time against FeatureModules for ctx[:customer_id]."
            mapping :input, key: :literal, value: :expression,
                            example: [{ "key" => "amount", "value" => "ctx[:model].fee" }],
                            description: "Inputs passed to the module. Each key is one of the module's input fields (amount) and each value is a Ruby expression over ctx (ctx[:model].fee). Unsafe or blank rows are dropped."
            enum :exitKind, EXIT_KINDS, default: "none",
                 description: "Where to send the visitor when the module finishes. none (default) uses the module's landing. page opens exitPage. url opens exitUrl (http/https only). route opens the named exitRoute."
            reference :exitPage, source: :pages, example: 1, visible: { exitKind: "page" },
                      description: "Launched page of this customer to open when the module finishes. Required when exitKind is page."
            literal :exitUrl, example: "https://example.test", placeholder: true, visible: { exitKind: "url" },
                    description: "http or https URL to open when the module finishes, such as https://example.test. javascript: and other schemes are rejected."
            literal :exitRoute, example: "customer_home", placeholder: true, visible: { exitKind: "route" },
                    description: "Named Rails route to open when the module finishes, such as customer_home. Required when exitKind is route."
            requires :exitPage, when: { exitKind: "page" }
            requires :exitUrl, when: { exitKind: "url" }
            requires :exitRoute, when: { exitKind: "route" }
            validate do |cfg, errors|
              next unless cfg["exitKind"].to_s == "url"

              url = cfg["exitUrl"].to_s.strip
              next if url.empty?

              uri = URI.parse(url)
              errors.add(:exitUrl, :invalid_url) unless %w[http https].include?(uri.scheme)
            rescue URI::InvalidURIError
              errors.add(:exitUrl, :invalid_url)
            end
          end

          def generate_body
            args = ["module_key: #{read(:moduleKey)}"]
            input = input_literal
            args << "input: #{input}" unless input == "{}"
            target = exit_target_literal
            args << "exit_target: #{target}" if target
            body("FlowchartRuntime::Handoff.request(ctx, #{args.join(', ')})")
          end

          private

          def exit_target_literal
            case value(:exitKind)
            when "page"
              %({"kind" => "page", "page_id" => #{read(:exitPage)}})
            when "url"
              %({"kind" => "url", "url" => #{read(:exitUrl)}})
            when "route"
              %({"kind" => "route", "name" => #{read(:exitRoute)}})
            end
          end

          def input_literal
            pairs = safe_expression_pairs(value(:input)).filter_map do |name, expression|
              next unless name.match?(INPUT_NAME)

              "#{literal(name)} => #{emit_expression(expression)}"
            end
            return "{}" if pairs.empty?

            "{#{pairs.join(', ')}}"
          end
        end
      end
    end
  end
end
