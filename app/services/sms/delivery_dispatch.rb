# frozen_string_literal: true

module Sms
  class DeliveryDispatch
    CLAIM_TTL = 30.minutes

    def self.claim(message_id, now: Time.current)
      token = SecureRandom.uuid
      changed = Message.where(id: message_id, status: "queued", dispatch_started_at: nil)
                       .delivery_due(now)
                       .where("delivery_claim_token IS NULL OR delivery_claimed_at <= ?", now - CLAIM_TTL)
                       .update_all(delivery_claim_token: token, delivery_claimed_at: now)
      [Message.find(message_id), token] if changed == 1
    end

    def self.blocked_status(message, now: Time.current)
      action = Campaigns::DeliveryPolicy.call(message: message, at: now)[:action]
      return "expired" if action == :expire
      "suppressed" if action == :suppress
    end

    def self.apply_block(message, token, now: Time.current)
      DispatchLocks.synchronize(message) do |_customer, _campaign, _contact, recipient|
        next false unless message.status == "queued" && message.dispatch_started_at.nil? &&
          message.delivery_claim_token == (token == :unclaimed ? nil : token)
        policy = Campaigns::DeliveryPolicy.call(message: message, at: now)
        next false unless %i[suppress expire].include?(policy[:action])
        apply_decision(message, recipient, policy, at: now)
        true
      end
    end

    # Caller owns ordered locks, and verified the current preparation fence.
    def self.apply_decision(message, recipient, decision, at:)
      case decision[:action]
      when :expire then message.mark_expired!
      when :suppress then message.mark_suppressed!
      when :defer
        message.update!(delivery_due_at: decision[:due_at], delivery_claim_token: nil, delivery_claimed_at: nil, delivery_enqueued_at: nil)
      end
      return unless recipient
      if decision[:action] == :defer
        recipient.update!(deferral_reason: decision[:reason].to_s, delivery_due_at: decision[:due_at])
      else
        recipient.update!(skip_reason: decision[:reason].to_s, deferral_reason: nil, processed_at: at, delivery_due_at: nil)
      end
    end

    def self.template_for(message)
      snapshot = message.metadata.fetch("template_snapshot")
      unless snapshot["provider"] == message.provider && snapshot["provider_code"].present? && snapshot["vars"].is_a?(Hash)
        raise Errors::TemplateVarsInvalid, I18n.t("sms.errors.snapshot_invalid")
      end
      Template.new(key: snapshot.fetch("key"), variables: snapshot.fetch("required_vars"),
                   provider_template_codes: { message.provider => snapshot.fetch("provider_code") })
    end

    # A single fenced update is the point of no return. A stale preparation
    # worker cannot start; lease expiry can never reclaim an attempted payload.
    def self.start(message, token, now: Time.current)
      credential = DeliveryCredential.for_message(message)
      DispatchLimiter.acquire(credential: credential, message: message, claim_token: token, at: now)[:action] == :started
    end

    def self.release(message, token)
      Message.where(id: message.id, status: "queued", delivery_claim_token: token, dispatch_started_at: nil)
             .update_all(delivery_claim_token: nil, delivery_claimed_at: nil, delivery_enqueued_at: nil)
    end
  end
end
