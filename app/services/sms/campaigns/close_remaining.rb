# frozen_string_literal: true

module Sms
  module Campaigns
    # Caller owns customer/campaign locks. Never recalls a durable attempt.
    class CloseRemaining
      def self.call(customer:, campaign:, reason:, at:)
        Sms::CampaignRecipient.where(customer_id: customer.id, campaign_id: campaign.id, status: %w[pending admitted])
          .find_in_batches(batch_size: Support::BATCH_SIZE) do |recipients|
          recipients.each do |recipient|
            Sms::Contact.find_by!(customer_id: customer.id, id: recipient.contact_id).lock!
            recipient.lock!
            message = recipient.message_id && Sms::Message.find_by!(id: recipient.message_id, customer_id: customer.id)
            message&.lock!
            next if message&.dispatch_started_at
            next if message && message.status != "queued"
            if message
              reason == :campaign_expired ? message.mark_expired! : message.mark_suppressed!
            end
            recipient.update!(status: reason == :campaign_cancelled ? "cancelled" : (message ? "admitted" : "skipped"),
              skip_reason: reason.to_s, deferral_reason: nil, processed_at: at, delivery_due_at: nil)
          end
        end
      end
    end
  end
end
