# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Communication
        class SendTemplateEmailGenerator < BaseGenerator
          generator_metadata do
            description "Sends a named Emails template for this customer. Use send_email when the " \
                        "subject and body are written on the step instead. Reads templateId, to " \
                        "(ctx path of the address), vars, optional cc/bcc/replyTo, locale " \
                        "(default ctx[:locale] or I18n.locale), and idempotencyKey. Writes " \
                        "resultVar (default email_message_id) with the ledger id. Fails with " \
                        "send_template_email.failed when the Email module rejects the send " \
                        "(missing template, credentials, or invalid vars)."
            category :communication
            version "2.2.0"
            presentation icon: "M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z",
                        color: "purple", single_use: false, privileged: false
          end

          config_schema do
            reference :templateId, source: :email_templates, required: true, example: 1,
                      description: "Emails template id for this customer. Pick the template the admin named; do not compose subject/body here."
            input :to, required: true, example: "user.email",
                  description: "ctx path of the recipient address, e.g. user.email or model.email. A member-owned record field is typical."
            mapping :vars, key: :literal, value: :literal, default: [],
                    description: "Template variable name to value. Static text, a number, or a ctx/ENV expression such as ctx[:user_name]."
            expression :cc, group: :advanced,
                       description: "Optional CC address expression, e.g. ctx[:manager_email] or \"ops@example.com\". Blank sends no CC."
            expression :bcc, group: :advanced,
                       description: "Optional BCC address expression, e.g. ctx[:auditor_email]. Blank sends no BCC."
            expression :replyTo, group: :advanced,
                       description: "Optional Reply-To address expression, e.g. \"support@example.com\". Blank uses the Email module From."
            expression :locale, default: "", example: "ctx[:locale]", group: :advanced,
                       description: "I18n locale while rendering and sending, e.g. \"zh-CN\" or ctx[:locale]. Blank uses ctx[:locale] or I18n.locale."
            expression :idempotencyKey,
                       description: "Optional Emails ledger idempotency key, e.g. ctx[:request_id]. Duplicate keys reuse the existing message."
            output :resultVar, default: "email_message_id",
                   description: "ctx key for the Emails::Message id (default email_message_id). Later steps read this integer."
          end

          def generate_body
            attempt('"send_template_email.failed"', Email::Errors::Error) do
              [assign(:resultVar, "FlowchartRuntime::TemplateEmail.deliver(#{deliver_args})")]
            end
          end

          private

          def deliver_args
            opts = [
              "ctx",
              "to: #{read(:to)}",
              "template_id: #{read(:templateId)}",
              "vars: #{vars_source}"
            ]
            opts << "cc: #{read(:cc)}" if value(:cc).to_s.strip.present?
            opts << "bcc: #{read(:bcc)}" if value(:bcc).to_s.strip.present?
            opts << "reply_to: #{read(:replyTo)}" if value(:replyTo).to_s.strip.present?
            opts << "locale: #{read(:locale)}" if value(:locale).to_s.strip.present?
            opts << "idempotency_key: #{read(:idempotencyKey)}" if value(:idempotencyKey).to_s.strip.present?
            opts.join(", ")
          end

          def vars_source
            pairs = Array(value(:vars)).filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              val = row.key?("value") ? row["value"] : row[:value]
              next if key.to_s.strip.empty?
              next unless safe_ident?(key.to_s)

              "#{key}: #{ruby_value(val)}"
            end
            return "{}" if pairs.empty?

            "{#{pairs.join(', ')}}"
          end

          def ruby_value(val)
            return "nil" if val.nil?
            return val.inspect if val == true || val == false || val.is_a?(Numeric)

            str = val.to_s.strip
            return "nil" if str.empty?
            return emit_expression(str) if dynamic_ruby?(str)

            str.inspect
          end

          def dynamic_ruby?(str)
            str.match?(/\A(?:ctx\[|ENV(?:\.|\[))/) && safe_single_expression?(str)
          end
        end
      end
    end
  end
end
