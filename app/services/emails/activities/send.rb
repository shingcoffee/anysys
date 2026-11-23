# frozen_string_literal: true

module Emails
  module Activities
    # Send orchestrates: idempotency → contract → render → resolve credential →
    # opt-out/suppression → race-safe persist → enqueue provider delivery.
    # Returns the persisted Emails::Message.
    class Send
      DEFAULT_DAILY_CAP = 1_000

      class << self
        def call(customer:, to:, template_id:, vars:, cc: nil, bcc: nil, reply_to: nil,
                 idempotency_key: nil, mode: nil, provider: nil, scheduled_at: nil)
          idempotency_key = idempotency_key.presence
          existing = PersistMessage.existing(customer_id: customer.id, idempotency_key: idempotency_key)
          return existing if existing

          contract = Email::Contracts::Send.new(Email::Contracts::Send::Input.new)
          unless contract.validate(customer_id: customer.id, to: to, template_id: template_id, vars: vars)
            raise Email::Errors::TemplateVarsInvalid, contract.errors.full_messages.to_sentence
          end

          template   = contract.template
          rendered   = TemplateRenderer.render(template: template, vars: vars)
          credential = Email::CredentialResolver.call(mode: mode || Email::CredentialResolver.default_mode, provider: provider)

          attrs = {
            customer: customer, email_template: template, to: to, from: credential.from_address,
            cc: cc, bcc: bcc, reply_to: reply_to,
            subject: rendered[:subject], body_html: rendered[:body_html], body_text: rendered[:body_text],
            message_type: "transactional", idempotency_key: idempotency_key, provider: credential.provider,
            delivery_due_at: scheduled_at || Time.current,
            metadata: {
              attachment_blob_ids: Emails::CompileTemplate.blob_ids_for(template),
              tracking_enabled: credential.tracking_enabled?,
              vars: vars
            }.merge(DeliveryCredential.metadata(credential))
          }

          MessageAdmission.validate!(credential: credential, attributes: attrs)

          # Suppression — recorded but never dispatched.
          if Emails::Suppression.suppressed?(customer_id: customer.id, email: to)
            message, _ = Quota.reserve(attrs.merge(status: "suppressed"))
            instrument("suppressed", credential.provider)
            return message
          end

          message, created = Quota.reserve(attrs.merge(status: "queued"))
          return message unless created

          DeliveryHandoff.call(message, mode: mode)
          message
        end

        def check_daily_cap!(customer)
          Quota.check_daily!(customer)
        end

        def daily_cap_for(customer)
          FeatureModules::DailyCap.for(
            customer: customer,
            module_key: "email",
            default: DEFAULT_DAILY_CAP,
            log_label: "[Emails::Activities::Send]"
          )
        end

        private

        def instrument(outcome, provider)
          ActiveSupport::Notifications.instrument("email.send", outcome: outcome, provider: provider, duration: nil)
        end
      end
    end
  end
end
