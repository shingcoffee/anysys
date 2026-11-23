# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Communication
        class SendEmailGenerator < BaseGenerator
          generator_metadata do
            description "Sends an email whose To, subject and body are written on this step " \
                        "(Liquid from ctx). Use send_template_email when the admin named an " \
                        "Emails template instead. Reads to/cc/bcc/replyTo templates, optional " \
                        "attachmentsVariable (a generate_document result, a generate_file or " \
                        "download_file file, a record's File or Image field, or blob ids), " \
                        "locale, and idempotencyKey. Delivers through Emails::Gateway.send_raw " \
                        "for ctx[:customer_id]. Writes resultVar (default email_message_ids) " \
                        "with ledger ids. onError continue (default) keeps the submission if " \
                        "delivery cannot start; fail refuses it with send_email.failed."
            category :communication
            version "1.1.0"
            presentation icon: "M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z",
                         color: "purple", single_use: false, privileged: false
          end

          config_schema do
            template :to, required: true, example: "sales@example.com", placeholder: true,
                     description: "Recipient addresses, comma/semicolon/space separated. May read " \
                                  "the record, e.g. {{ model.email }} or sales@example.com."
            template :subject, required: true, example: "New order {{ model.order_number }}", placeholder: true,
                     description: "Subject line. Record values go in {{ }}, e.g. New order {{ model.order_number }}."
            template :body, required: true, multiline: true, placeholder: true,
                     example: "Order {{ model.order_number }} was placed. Total: {{ model.total }}",
                     description: "Plain-text body. {{ }} placeholders resolve from ctx. HTML is escaped; newlines become <br>."
            template :cc, default: "", placeholder: true, group: :advanced,
                     description: "Carbon-copy addresses, same format as to. Blank sends no CC. Example: manager@example.com."
            template :bcc, default: "", placeholder: true, group: :advanced,
                     description: "Blind carbon-copy addresses, same format as to. Blank sends no BCC. Example: audit@example.com."
            template :replyTo, default: "", placeholder: true, group: :advanced,
                     description: "Reply-To address. Blank uses the Email module From address. Example: support@example.com."
            expression :locale, default: "", example: "ctx[:locale]", group: :advanced,
                       description: "I18n locale while sending, e.g. \"zh-CN\" or ctx[:locale]. Blank uses ctx[:locale] or I18n.locale."
            input :attachmentsVariable, default: "", example: "document", group: :advanced,
                  description: "ctx path of a generate_document result (blob_id hash), a generate_file or download_file " \
                               "file ({filename, content, content_type}), a record's File or Image field such as " \
                               "model.contract, an array of those, or blob ids. Blank sends no files."
            expression :idempotencyKey, group: :advanced,
                       description: "Optional Emails ledger idempotency key, e.g. ctx[:request_id]. Duplicate keys reuse the existing message."
            enum :onError, FlowchartRuntime::InlineEmail::ON_ERRORS, default: "continue",
                 description: "continue (default) keeps the submission if the email cannot go out. " \
                              "fail refuses the submission with send_email.failed."
            output :resultVar, default: "email_message_ids",
                   description: "ctx key for the array of Emails::Message ids (default email_message_ids). Empty array when onError is continue and send failed."
          end

          def generate_body
            attempt('"send_email.failed"', FlowchartRuntime::Template::Error) do
              [
                "ids = FlowchartRuntime::InlineEmail.deliver(#{deliver_args})",
                "next false if ids == false",
                assign(:resultVar, "ids")
              ]
            end
          end

          private

          def deliver_args
            [
              "ctx",
              "to: #{read(:to)}",
              "subject: #{read(:subject)}",
              "body: #{read(:body)}",
              ("cc: #{read(:cc)}" if value(:cc).to_s.strip.present?),
              ("bcc: #{read(:bcc)}" if value(:bcc).to_s.strip.present?),
              ("reply_to: #{read(:replyTo)}" if value(:replyTo).to_s.strip.present?),
              ("locale: #{read(:locale)}" if value(:locale).to_s.strip.present?),
              ("attachments: #{read(:attachmentsVariable)}" if value(:attachmentsVariable).to_s.strip.present?),
              ("idempotency_key: #{read(:idempotencyKey)}" if value(:idempotencyKey).to_s.strip.present?),
              ("on_error: #{read(:onError)}" unless value(:onError) == "continue")
            ].compact.join(", ")
          end
        end
      end
    end
  end
end
