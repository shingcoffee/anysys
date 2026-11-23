# frozen_string_literal: true

module Emails
  module SendActivities
    class RunDispatch
      def self.claim(campaign, now: Time.current)
        token = SecureRandom.uuid
        changed = SendActivity.where(id: campaign.id, status: "processing")
                              .where("deferred_until IS NULL OR deferred_until <= ?", now)
                              .where("fanout_claim_token IS NULL OR fanout_claimed_at <= ?", now - SendActivity::CLAIM_TTL)
                              .update_all(fanout_claim_token: token, fanout_claimed_at: now,
                                          claimed_at: now, progressed_at: now, deferred_reason: nil, deferred_until: nil)
        token if changed == 1
      end

      def self.owned?(campaign, token)
        SendActivity.exists?(id: campaign.id, status: "processing", fanout_claim_token: token)
      end

      def self.heartbeat(campaign, token)
        SendActivity.where(id: campaign.id, status: "processing", fanout_claim_token: token)
                    .update_all(claimed_at: Time.current, fanout_claimed_at: Time.current, progressed_at: Time.current)
      end

      def self.defer(campaign, token, until_time:, reason:)
        SendActivity.where(id: campaign.id, status: "processing", fanout_claim_token: token)
                    .update_all(deferred_until: until_time, deferred_reason: reason,
                                claimed_at: Time.current, fanout_claim_token: nil, fanout_claimed_at: nil) == 1
      end

      def self.release(campaign, token)
        SendActivity.where(id: campaign.id, fanout_claim_token: token)
                    .update_all(fanout_claim_token: nil, fanout_claimed_at: nil)
      end
    end
  end
end
