# frozen_string_literal: true

module Sms
  class DispatchLimiter
    def self.rate_for(credential)
      value = credential.config_value("sender_rate_per_second", 1.0)
      rate = Float(value)
      return rate if rate.finite? && rate.positive? && rate <= 1.0
      raise Errors::TemplateVarsInvalid, I18n.t("sms_campaigns.errors.account_rate_invalid")
    rescue ArgumentError, TypeError
      raise Errors::TemplateVarsInvalid, I18n.t("sms_campaigns.errors.account_rate_invalid")
    end

    def self.acquire(credential:, message:, claim_token:, at:)
      now = at
      result = DispatchLocks.synchronize(message) do |_customer, _campaign, _contact, recipient|
        unless message.status == "queued" && message.dispatch_started_at.nil? && message.delivery_claim_token == claim_token
          next result(:lost_claim)
        end
        now = [at, Time.current].max
        policy = Campaigns::DeliveryPolicy.call(message: message, at: now)
        if policy[:action] != :allow
          DeliveryDispatch.apply_decision(message, recipient, policy, at: now)
          next result(policy[:action], due_at: policy[:due_at], reason: policy[:reason])
        end
        # Retained identity, never today's active/default credential.
        pinned = DeliveryCredential.for_message(message)
        raise Errors::CredentialsMissing, I18n.t("admin_modules.sms.errors.credentials_missing") unless pinned.id == credential.id
        pinned.lock!
        # Waiting for either tenant or account locks must not backdate a durable
        # authorization. The clock is sampled again at the locked boundary.
        now = [at, Time.current].max
        policy = Campaigns::DeliveryPolicy.call(message: message, at: now)
        if policy[:action] != :allow
          DeliveryDispatch.apply_decision(message, recipient, policy, at: now)
          next result(policy[:action], due_at: policy[:due_at], reason: policy[:reason])
        end
        if pinned.dispatch_next_at && pinned.dispatch_next_at > now
          policy = Campaigns::DeliveryPolicy.bounded_defer(message, pinned.dispatch_next_at, :account_rate)
          DeliveryDispatch.apply_decision(message, recipient, policy, at: now)
          next result(policy[:action], due_at: policy[:due_at], reason: policy[:reason])
        end
        rate = rate_for(pinned)
        changed = Message.where(id: message.id, status: "queued", dispatch_started_at: nil, delivery_claim_token: claim_token)
          .delivery_due(now).where("expires_at > ?", now)
          .update_all(["dispatch_started_at = ?, delivery_attempts = delivery_attempts + 1, updated_at = ?", now, now])
        next result(:lost_claim) unless changed == 1
        pinned.update!(dispatch_next_at: now + 1.0 / rate)
        recipient&.update!(deferral_reason: nil, delivery_due_at: nil, processed_at: now)
        result(:started, attempt_started_at: now)
      end
      if result[:action] == :defer
        DeliveryHandoff.call(message, now: now)
      end
      result
    end

    def self.result(action, due_at: nil, reason: nil, attempt_started_at: nil)
      { action: action, due_at: due_at, reason: reason, attempt_started_at: attempt_started_at }
    end
  end
end
