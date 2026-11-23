# frozen_string_literal: true

module Sms
  module Campaigns
    class Launch
      def self.call(customer:, actor:, campaign:, lock_version:, review_token:, at: Time.current)
        return Support.failure(:forbidden) unless Support.actor_allowed?(customer, actor)
        return Support.failure(:not_found) unless Support.scoped?(customer, campaign)
        payload = ReviewToken.read(review_token, at: at)
        return Support.failure(:review_changed) unless payload

        Quota.synchronize(customer) do
          campaign.lock!
          if campaign.status != "draft"
            next replay(customer, campaign, payload, lock_version)
          end
          next Support.failure(:review_changed) unless lock_version.to_s == campaign.lock_version.to_s
          contract, failure = DraftInput.build(customer: customer, campaign: campaign, attributes: {})
          next failure if failure
          template = contract.template
          template&.lock!
          contract.segment&.lock!
          credential = begin
            Sms::CredentialResolver.call
          rescue Sms::Errors::CredentialsMissing
            nil
          end
          next Support.failure(:credentials_missing) unless credential&.configured?
          next Support.failure(:template_required) unless template
          audience = Snapshot.audience(customer, contract.segment)
          binding = ReviewToken.binding(customer: customer, campaign: campaign, template: Snapshot.template(template, credential),
            audience: audience, credential_id: credential.id, credential_mode: credential.mode, provider: credential.provider)
          next Support.failure(:review_changed) unless binding == payload
          preview = Preview.call(customer: customer, actor: actor, campaign: campaign, at: at)
          next preview unless preview.success?
          next Support.failure(preview.value[:blockers].first) if preview.value[:blockers].any?

          settings = Snapshot.settings(campaign, template: template, credential: credential, at: at)
          campaign.update!(status: "scheduled", launched_by_id: actor.id, launched_at: at,
            expires_at: Time.iso8601(settings.fetch("expires_at")),
            settings_snapshot: settings, audience_snapshot: audience)
          # The scheduler claims a token; this accelerator invokes that same claim path.
          ActiveRecord.after_all_transactions_commit do
            begin
              SchedulerJob.perform_later
            rescue StandardError => error
              Rails.logger.warn("[sms.campaign.launch] campaign=#{campaign.id} #{error.class}")
            end
          end
          Support.success(campaign)
        end
      rescue ActiveRecord::StaleObjectError
        Support.failure(:review_changed)
      end

      def self.replay(customer, campaign, payload, version)
        return Support.failure(:review_changed) if campaign.status == "cancelled" ||
          version.to_s != campaign.settings_snapshot["draft_lock_version"].to_s
        original = campaign.dup
        binding = ReviewToken.binding(customer: customer, campaign: original,
          template: campaign.settings_snapshot["template"], audience: campaign.audience_snapshot,
          credential_id: campaign.settings_snapshot["credential_id"], credential_mode: campaign.settings_snapshot["credential_mode"],
          provider: campaign.settings_snapshot["provider"])
        binding["campaign_id"] = campaign.id
        binding == payload ? Support.success(campaign) : Support.failure(:review_changed)
      end
    end
  end
end
