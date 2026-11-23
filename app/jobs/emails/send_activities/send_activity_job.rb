# frozen_string_literal: true

module Emails
  module SendActivities
    class SendActivityJob < ApplicationJob
      queue_as :default

      BATCH_SIZE = 500
      THROTTLE_PER_MINUTE = Quota::CAMPAIGN_PER_MINUTE

      retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, error|
        campaign = SendActivity.find_by(id: job.arguments.first)
        if campaign
          campaign.with_lock do
            if campaign.status == "processing" && campaign.fanout_claim_token.nil?
              campaign.update_columns(status: "failed", stats: campaign.stats.merge(
                "failure_reason" => I18n.t("admin_modules.emails.send_activities.dead_letter.stuck_reason")
              ))
            end
          end
        end
        Rails.logger.error("[email_send_activity] exhausted campaign=#{job.arguments.first}: #{error.class}: #{error.message}")
      end

      def perform(send_activity_id)
        campaign = SendActivity.find_by(id: send_activity_id)
        return unless campaign && campaign.status == "processing"
        return unless FeatureModules::Module.enabled?(key: "email", customer_id: campaign.customer_id)

        token = RunDispatch.claim(campaign)
        return unless token

        campaign.reload
        audience = remaining_audience(campaign)
        if audience.none?
          finalize(campaign, token)
          return
        end

        if remaining_daily_cap(campaign.customer) <= 0
          defer_run(campaign, token, until_time: Time.current.tomorrow.beginning_of_day, reason: "daily_cap")
          return
        end
        allowance = Quota.campaign_allowance(campaign.customer, limit: THROTTLE_PER_MINUTE)
        if allowance.zero?
          defer_run(campaign, token, until_time: 1.minute.from_now, reason: "minute_cap")
          return
        end

        blob_ids = Emails::CompileTemplate.blob_ids_for(campaign.email_template)
        credential = Email::CredentialResolver.call(mode: Email::CredentialResolver.default_mode)
        processed = 0
        audience.find_each do |user|
          return unless RunDispatch.owned?(campaign, token)

          # Quota.reserve rechecks/reserves each recipient atomically; this
          # allowance is only a batch bound, never authorization to overspend.
          Emails::Gateway.queue_for_send_activity(
            send_activity: campaign, user: user, attachment_blob_ids: blob_ids,
            credential: credential, idempotency_key: "send-activity-#{campaign.id}-user-#{user.id}",
            campaign_limit: THROTTLE_PER_MINUTE
          )
          processed += 1
          RunDispatch.heartbeat(campaign, token)
          next if processed < [BATCH_SIZE, allowance].min

          RefreshStats.call(campaign)
          if remaining_audience(campaign).exists?
            defer_run(campaign, token, until_time: 1.minute.from_now, reason: "batch")
          else
            finalize(campaign, token)
          end
          return
        end
        finalize(campaign, token)
      rescue Email::Errors::DailyCapExceeded
        defer_run(campaign, token, until_time: Time.current.tomorrow.beginning_of_day, reason: "daily_cap")
      rescue Quota::Throttled
        defer_run(campaign, token, until_time: 1.minute.from_now, reason: "minute_cap")
      ensure
        RunDispatch.release(campaign, token) if campaign && token
      end

      def self.remaining_daily_cap(customer)
        Quota.remaining_daily(customer)
      end

      private

      def remaining_daily_cap(customer)
        self.class.remaining_daily_cap(customer)
      end

      def remaining_audience(campaign)
        ids = Message.where(customer_id: campaign.customer_id, email_send_activity_id: campaign.id)
                     .where("json_extract(metadata, '$.user_id') IS NOT NULL")
                     .select(Arel.sql("CAST(json_extract(metadata, '$.user_id') AS INTEGER)"))
        campaign.audience.where.not(id: ids)
      end

      def defer_run(campaign, token, until_time:, reason:)
        RefreshStats.call(campaign)
        return unless RunDispatch.defer(campaign, token, until_time: until_time, reason: reason)

        self.class.set(wait_until: until_time).perform_later(campaign.id)
      end

      def finalize(campaign, token)
        RefreshStats.call(campaign)
        return unless campaign.complete!(run_token: token)

        ActiveSupport::Notifications.instrument("email_send_activity.lifecycle", event: "completed",
                                               send_activity_id: campaign.id, recipients: campaign.stats["sent_count"])
      end
    end
  end
end
