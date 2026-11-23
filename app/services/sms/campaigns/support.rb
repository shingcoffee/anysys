# frozen_string_literal: true

module Sms
  module Campaigns
    module Support
      MAX_AUDIENCE = 10_000
      BATCH_SIZE = 100
      LEASE = 15.minutes

      module_function

      def success(value)
        Sms::Result.new(success: true, value: value, errors: {}, code: nil)
      end

      def failure(code, field: :base, errors: nil)
        Sms::Result.new(success: false, value: nil, code: code,
                        errors: errors || { field => [I18n.t("sms_campaigns.errors.#{code}")] })
      end

      def scoped?(customer, record)
        customer&.persisted? && record&.persisted? && record.customer_id == customer.id
      end

      def actor_allowed?(customer, actor)
        Sms::DomainAccess.actor_allowed?(customer, actor)
      end

      def enabled?(customer)
        FeatureModules::Module.enabled?(key: "sms", customer_id: customer.id)
      end

      def lease_valid?(campaign, token, at)
        token.present? && campaign.run_token == token && campaign.run_lease_expires_at &&
          campaign.run_lease_expires_at > at && %w[scheduled running].include?(campaign.status)
      end

      def enqueue(customer_id, campaign_id, token, due_at: nil)
        ActiveRecord.after_all_transactions_commit do
          begin
            job = due_at ? RunJob.set(wait_until: due_at) : RunJob
            job.perform_later(customer_id, campaign_id, token)
          rescue StandardError => error
            Rails.logger.warn("[sms.campaign.handoff] campaign=#{campaign_id} #{error.class}")
          end
        end
      end

      def iso(time)
        time&.to_time&.utc&.iso8601(6)
      end

      def intended_start(campaign, at)
        campaign.send_timing == "scheduled" ? campaign.scheduled_at : at
      end
    end
  end
end
