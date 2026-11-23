# frozen_string_literal: true

module Emails
  class DeliveryDispatch
    CLAIM_TTL = 30.minutes
    MAX_ATTEMPTS = 3

    def self.claim(message_id, now: Time.current)
      token = SecureRandom.uuid
      changed = Message.where(id: message_id, status: "queued")
                       .where("delivery_due_at IS NULL OR delivery_due_at <= ?", now)
                       .where("delivery_claim_token IS NULL OR delivery_claimed_at <= ?", now - CLAIM_TTL)
                       .where("delivery_attempts < ?", MAX_ATTEMPTS)
                       .update_all(["delivery_claim_token = ?, delivery_claimed_at = ?, delivery_attempts = delivery_attempts + 1", token, now])
      return unless changed == 1

      [Message.find(message_id), token]
    end

    def self.blocked?(message)
      return true if Suppression.suppressed?(customer_id: message.customer_id, email: message.to)
      return false unless message.message_type == "campaign"

      campaign = SendActivities::SendActivity.find_by(id: message.email_send_activity_id, customer_id: message.customer_id)
      campaign.nil? || %w[cancelled failed].include?(campaign.status)
    end

    def self.release(message, token)
      Message.where(id: message.id, status: "queued", delivery_claim_token: token)
             .update_all(delivery_claim_token: nil, delivery_claimed_at: nil, delivery_enqueued_at: nil)
    end
  end
end
