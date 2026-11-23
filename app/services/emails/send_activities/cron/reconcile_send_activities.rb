# frozen_string_literal: true

module Emails
  module SendActivities
    module Cron
      # Recovers campaigns stuck in `processing` because their SendActivityJob died
      # (worker crash, deploy) and never re-enqueued itself. Re-claims each stalled
      # campaign atomically (so overlapping reaper runs don't pile up jobs) and
      # re-drives the send — safe because per-recipient idempotency skips everyone
      # already emailed. Cross-tenant by design (no Current.customer).
      class ReconcileSendActivities
        def self.call
          Emails::SendActivities::SendActivity.stalled_sending.find_each do |campaign|
            next unless FeatureModules::Module.enabled?(key: "email", customer_id: campaign.customer_id)

            # Explicit deferrals remain protected AFTER the cap resets, until
            # a worker resumes them. fail_stalled! also measures latest progress
            # rather than killing a healthy long-running campaign by start age.
            at_cap = Emails::SendActivities::SendActivityJob.remaining_daily_cap(campaign.customer) <= 0
            if campaign.deferred_reason.nil? && !at_cap && Emails::SendActivities::SendActivity.fail_stalled!(
              campaign, reason: I18n.t("admin_modules.emails.send_activities.dead_letter.stuck_reason")
            )
              Rails.logger.error("[email_send_activity] dead-lettering stuck campaign=#{campaign.id} (sending > #{Emails::SendActivities::SendActivity::MAX_SENDING_AGE.inspect})")
              next
            end

            next unless Emails::SendActivities::SendActivity.reclaim_stalled!(campaign.id)

            Rails.logger.warn("[email_send_activity] re-driving stalled campaign=#{campaign.id}")
            Emails::SendActivities::SendActivityJob.perform_later(campaign.id)
          rescue StandardError => e
            Rails.logger.warn("[email_send_activity] reaper failed campaign=#{campaign.id}: #{e.class}: #{e.message}")
          end
        end
      end
    end
  end
end
