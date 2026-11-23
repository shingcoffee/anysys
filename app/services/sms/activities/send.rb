# frozen_string_literal: true

module Sms
  module Activities
    # Admission only: the committed ledger is the outbox, enqueue its accelerator
    # after every enclosing transaction has committed.
    class Send
      DEFAULT_DAILY_CAP = 1_000

      def self.call(customer:, to:, template_key:, vars:, idempotency_key: nil, mode: nil, provider: nil, expires_at: nil)
        request = MessageAdmission.new(to: to, template_key: template_key, vars: vars,
                                       idempotency_key: idempotency_key, mode: mode, provider: provider, expires_at: expires_at)
        existing = MessageAdmission.existing(customer, request.idempotency_key)
        return request.replay!(existing) if existing

        message, created = Quota.synchronize(customer) do
          existing = MessageAdmission.existing(customer, request.idempotency_key)
          next [request.replay!(existing), false] if existing

          unless FeatureModules::Module.enabled?(key: "sms", customer_id: customer.id)
            raise Errors::ModuleDisabled, I18n.t("sms.errors.module_disabled")
          end

          template = request.validate_template!
          request.marketing_contact!(customer, template)
          suppressed = OptOut.opted_out?(customer_id: customer.id, phone_e164: request.to)
          credential = unless suppressed
            CredentialResolver.call(mode: request.mode || CredentialResolver.default_mode, provider: request.provider)
          end
          request.validate_provider!(template, credential) if credential
          unless suppressed
            Quota.check_rate_limit!(customer_id: customer.id, to: request.to, windows: credential.adapter_class.rate_limit_windows)
            Quota.check_daily!(customer)
          end
          request.persist(customer: customer, template: template, credential: credential, suppressed: suppressed)
        end

        if created && message.status == "queued"
          ActiveRecord.after_all_transactions_commit { DeliveryHandoff.call(message) }
        elsif created
          ActiveSupport::Notifications.instrument("sms.send", outcome: "suppressed", provider: message.provider, duration: nil)
        end
        message
      end

      def self.call_campaign(customer:, recipient:, at: nil)
        raise ActiveRecord::RecordNotFound unless customer.persisted? && recipient.persisted?
        message = Quota.synchronize(customer) do
          identity = CampaignRecipient.find_by!(id: recipient.id, customer_id: customer.id)
          campaign = Campaign.find_by!(customer_id: customer.id, id: identity.campaign_id)
          campaign.lock!
          contact = Contact.find_by!(customer_id: customer.id, id: identity.contact_id)
          contact.lock!
          persisted = CampaignRecipient.find_by!(customer_id: customer.id, campaign_id: campaign.id, id: recipient.id)
          persisted.lock!
          admission_at = [at || Time.current, Time.current].max
          request = MessageAdmission.for_campaign(customer: customer, recipient: persisted)
          if (existing = MessageAdmission.existing(customer, request.idempotency_key))
            existing = request.replay!(existing)
            unless existing.campaign_id == campaign.id && existing.contact_id == contact.id &&
              (!persisted.message_id || persisted.message_id == existing.id)
              raise Errors::IdempotencyConflict, I18n.t("sms.errors.idempotency_conflict")
            end
            persisted.update!(message_id: existing.id, status: "admitted", admitted_at: persisted.admitted_at || existing.created_at)
            next existing
          end
          raise Errors::IdempotencyConflict, I18n.t("sms.errors.idempotency_conflict") if persisted.message_id
          raise Errors::ModuleDisabled, I18n.t("sms.errors.module_disabled") unless Campaigns::Support.enabled?(customer)
          template = request.campaign_template
          request.marketing_contact!(customer, template)
          credential = request.campaign_credential
          request.validate_provider!(template, credential)
          decision = Campaigns::DeliveryPolicy.call(message: Message.new(customer_id: customer.id, campaign_id: campaign.id,
            contact_id: contact.id, to: persisted.phone_e164, expires_at: campaign.expires_at,
            metadata: { "template_snapshot" => { "purpose" => "marketing" } }), at: admission_at)
          unless decision[:action] == :allow
            raise Errors::MarketingIneligible.new(reason: decision[:reason])
          end
          Quota.check_rate_limit!(customer_id: customer.id, to: request.to, windows: credential.adapter_class.rate_limit_windows)
          Quota.check_daily!(customer)
          admitted, = request.persist(customer: customer, template: template, credential: credential)
          persisted.update!(message_id: admitted.id, status: "admitted", admitted_at: admission_at,
                            deferral_reason: nil, delivery_due_at: nil)
          ActiveRecord.after_all_transactions_commit { DeliveryHandoff.call(admitted) }
          admitted
        end
        recipient.reload
        message
      end

      def self.daily_cap_for(customer)
        FeatureModules::DailyCap.for(customer: customer, module_key: "sms", default: DEFAULT_DAILY_CAP,
                                    log_label: "[Sms::Activities::Send]")
      end
    end
  end
end
