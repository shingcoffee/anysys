# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Communication
        class SendSmsGenerator < BaseGenerator
          generator_metadata do
            description "Sends an SMS through an approved customer template (no free-text body; " \
                        "carriers require templates). Reads templateKey, to (ctx path, default " \
                        "model.phone), vars, and optional idempotencyKey. Writes resultVar " \
                        "(default sms_message_id) with the tenant ledger id. Fails with " \
                        "send_sms.suppressed, quota, invalid_number, template_missing, " \
                        "invalid_vars, credentials_missing, module_disabled, " \
                        "idempotency_conflict, marketing_ineligible, provider_code_missing, " \
                        "api_error, or failed. Tenant-scoped to ctx[:customer_id]."
            category :communication
            version "1.1.0"
            presentation icon: "M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9",
                        color: "amber", single_use: false, privileged: false
          end

          config_schema do
            reference :templateKey, source: :sms_templates, required: true, example: "verify_code",
                      description: "Approved SMS template key for this customer, e.g. verify_code. Free-text bodies are not sent."
            input :to, default: "model.phone",
                  description: "ctx path of the recipient E.164 phone number, e.g. model.phone or user.mobile. Default model.phone."
            mapping :vars, key: :literal, value: :expression, default: [],
                    description: "Template variable name to Ruby expression, e.g. code => ctx[:otp] or minutes => \"5\"."
            expression :idempotencyKey,
                       description: "Optional SMS ledger idempotency key, e.g. ctx[:request_id]. Duplicate keys with different payloads fail with send_sms.idempotency_conflict."
            output :resultVar, default: "sms_message_id",
                   description: "ctx key for the Sms::Message id (default sms_message_id). Later steps read this integer."
          end

          def generate_body
            attempt('"send_sms.failed"', FlowchartRuntime::SmsDelivery::Error) do
              [assign(:resultVar, "FlowchartRuntime::SmsDelivery.deliver(ctx, #{deliver_args})")]
            end
          end

          private

          def deliver_args
            opts = [
              "customer: Customer.find_by(id: ctx[:customer_id])",
              "to: #{read(:to)}",
              "template_key: #{read(:templateKey)}"
            ]
            opts << "vars: #{vars_source}" unless vars_source == "{}"
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

              "#{key}: #{expression_source(val)}"
            end
            return "{}" if pairs.empty?

            "{#{pairs.join(', ')}}"
          end

          def expression_source(val)
            return "nil" if val.nil?

            str = val.to_s.strip
            return "nil" if str.empty?
            return emit_expression(str) if safe_single_expression?(str)

            str.inspect
          end
        end
      end
    end
  end
end
