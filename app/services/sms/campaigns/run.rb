# frozen_string_literal: true

module Sms
  module Campaigns
    class Run
      def self.call(customer:, campaign:, run_token:, at: Time.current, limit: 100)
        return empty unless Support.scoped?(customer, campaign)
        limit = limit.is_a?(Integer) ? limit.clamp(1, Support::BATCH_SIZE) : Support::BATCH_SIZE
        ready = Quota.synchronize(customer) do
          campaign.lock!
          now = current_time(at)
          next false unless Support.lease_valid?(campaign, run_token, now)
          next false if campaign.send_timing == "scheduled" && campaign.scheduled_at && campaign.scheduled_at > now
          renew_lease(campaign, now)
          if campaign.expires_at.nil? || campaign.expires_at <= now
            if campaign.started_at
              CloseRemaining.call(customer: customer, campaign: campaign, reason: :campaign_expired, at: now)
              Completion.call(customer: customer, campaign: campaign, at: now)
              RefreshStats.call(customer: customer, campaign: campaign, at: now)
            else
              fail_campaign(customer, campaign, :campaign_expired, now)
            end
            next false
          end
          next false unless campaign.started_at || snapshot_audience(customer, campaign, now)
          true
        end
        return empty unless ready

        processed = 0
        ids = pending(customer, campaign).where("delivery_due_at IS NULL OR delivery_due_at <= ?", current_time(at)).order(:id).limit(limit).pluck(:id)
        ids.each do |id|
          changed = Quota.synchronize(customer) do
            campaign.lock!
            recipient = Sms::CampaignRecipient.find_by!(customer_id: customer.id, campaign_id: campaign.id, id: id)
            contact = Sms::Contact.find_by!(customer_id: customer.id, id: recipient.contact_id)
            contact.lock!
            recipient.lock!
            now = current_time(at)
            next false unless Support.lease_valid?(campaign, run_token, now)
            next false unless recipient.status == "pending" && (!recipient.delivery_due_at || recipient.delivery_due_at <= now)
            renew_lease(campaign, now)
            process(customer, campaign, contact, recipient, now)
            true
          end
          processed += 1 if changed
        end
        Quota.synchronize(customer) do
          campaign.lock!
          now = current_time(at)
          next empty(processed) unless Support.lease_valid?(campaign, run_token, now)
          renew_lease(campaign, now)
          Completion.call(customer: customer, campaign: campaign, at: now)
          RefreshStats.call(customer: customer, campaign: campaign, at: now)
          next empty(processed) unless campaign.status == "running"
          scope = pending(customer, campaign)
          queued = Sms::Message.where(customer_id: customer.id, campaign_id: campaign.id, status: "queued", dispatch_started_at: nil)
          has_more = scope.exists? || queued.exists?
          due = [scope.minimum(:delivery_due_at), queued.minimum(:delivery_due_at)].compact.min
          due = now if scope.where(delivery_due_at: nil).exists? || queued.where(delivery_due_at: nil).exists?
          { processed_count: processed, has_more: has_more, next_run_at: has_more ? (due || now + 1.minute) : nil }
        end
      end

      def self.snapshot_audience(customer, campaign, at)
        unless Snapshot.valid?(campaign) && Sms::Audience::SegmentQuery.valid?(customer: customer,
          rules: campaign.audience_snapshot["segment_rules"], field_specs: campaign.audience_snapshot["field_specs"])
          fail_campaign(customer, campaign, :template_invalid, at)
          return false
        end
        relation = Sms::Audience::SegmentQuery.call(customer: customer, rules: campaign.audience_snapshot.fetch("segment_rules"),
                                                  field_specs: campaign.audience_snapshot.fetch("field_specs"))
        if relation.limit(Support::MAX_AUDIENCE + 1).count > Support::MAX_AUDIENCE
          fail_campaign(customer, campaign, :audience_too_large, at)
          return false
        end
        settings = campaign.settings_snapshot
        # Complete ledger + started_at share one bounded database transaction.
        # Only 100 payloads live in Ruby at once, never a whole-tenant array.
        relation.find_in_batches(batch_size: Support::BATCH_SIZE) do |contacts|
          rows = contacts.map do |contact|
            input = Snapshot.contact(contact)
            vars = VariableMap.resolve(map: settings.fetch("variable_map"), snapshot: input, customer: customer, contact: contact)
            eligible = Eligibility.call(customer: customer, contact: contact, phone_e164: contact.phone_e164,
                                        vars: vars, settings: settings, at: at)
            input["eligibility_at_start"] = { "eligible" => eligible[:eligible], "reason" => eligible[:reason]&.to_s }
            { customer_id: customer.id, campaign_id: campaign.id, contact_id: contact.id, phone_e164: contact.phone_e164,
              contact_snapshot: input, vars: vars || {}, status: eligible[:eligible] ? "pending" : "skipped",
              skip_reason: eligible[:reason]&.to_s, processed_at: eligible[:eligible] ? nil : at, created_at: at, updated_at: at }
          end
          Sms::CampaignRecipient.insert_all!(rows)
        end
        campaign.update!(started_at: at, status: "running")
        RefreshStats.call(customer: customer, campaign: campaign, at: at)
        true
      end

      def self.process(customer, campaign, contact, recipient, at)
        settings = campaign.settings_snapshot
        decision = Eligibility.call(customer: customer, contact: contact, phone_e164: recipient.phone_e164,
          vars: SendStandards.vars_valid?(recipient.vars) ? recipient.vars : nil, settings: settings, at: at)
        unless decision[:eligible]
          skip(recipient, decision[:reason], at)
          return
        end
        if campaign.expires_at <= at
          skip(recipient, :campaign_expired, at)
          return
        end
        unless Support.enabled?(customer)
          skip(recipient, :module_disabled, at)
          return
        end
        zone = Schedule.valid_zone?(contact.timezone) ? contact.timezone : settings.fetch("timezone")
        quiet_due = QuietWindow.next_allowed(at: at, timezone: zone,
          start_hour: settings.fetch("quiet_hours_start"), end_hour: settings.fetch("quiet_hours_end"))
        if quiet_due > at
          defer(recipient, campaign, :quiet_hours, quiet_due, at)
          return
        end
        reservations = Sms::CampaignRecipient.where(customer_id: customer.id, campaign_id: campaign.id)
          .where(admitted_at: (at - 60.seconds)..at).order(:admitted_at)
        if reservations.count >= settings.fetch("send_rate_per_minute")
          defer(recipient, campaign, :campaign_rate, reservations.pick(:admitted_at) + 60.seconds + 0.000001, at)
          return
        end
        credential = Sms::Credential.find_by(id: settings.fetch("credential_id"), provider: settings.fetch("provider"), mode: settings.fetch("credential_mode"))
        unless credential&.configured?
          fail_campaign(customer, campaign, :credentials_missing, at)
          return
        end
        quota = quota_decision(customer, recipient.phone_e164, credential, at)
        if quota
          quota[:due_at] ? defer(recipient, campaign, quota[:reason], quota[:due_at], at) : skip(recipient, quota[:reason], at)
          return
        end
        Sms::Gateway.send_campaign(customer: customer, recipient: recipient, at: at)
      rescue Sms::Errors::MarketingIneligible => error
        skip(recipient, error.reason, at)
      rescue Sms::Errors::DailyCapExceeded
        defer(recipient, campaign, :daily_cap, at.next_day.beginning_of_day, at)
      rescue Sms::Errors::RateLimited
        decision = quota_decision(customer, recipient.phone_e164, credential, at)
        decision && decision[:due_at] ? defer(recipient, campaign, decision[:reason], decision[:due_at], at) : skip(recipient, :rate_limited, at)
      rescue Sms::Errors::TemplateVarsInvalid, Sms::Errors::CredentialsMissing => error
        fail_campaign(customer, campaign, error.is_a?(Sms::Errors::CredentialsMissing) ? :credentials_missing : :template_invalid, at)
      end

      def self.quota_decision(customer, phone, credential, at)
        cap = Sms::Activities::Send.daily_cap_for(customer)
        return { reason: :daily_cap_exceeded, due_at: nil } if cap.zero?
        used = Sms::Message.where(customer_id: customer.id).where.not(status: %w[suppressed failed expired]).where(created_at: at.beginning_of_day..at).count
        return { reason: :daily_cap, due_at: at.next_day.beginning_of_day } if used >= cap
        windows = credential.adapter_class.rate_limit_windows
        lookback = windows.map { |_name, seconds, _limit| seconds }.max
        return nil unless lookback
        recent = Sms::Message.rate_limit_window(customer_id: customer.id, to: phone, since: at - lookback)
        due = windows.filter_map do |_name, seconds, limit|
          times = recent.select { |time| time >= at - seconds }.sort
          times[-limit] + seconds + 0.000001 if times.size >= limit
        end.max
        { reason: :phone_window, due_at: due } if due
      end

      def self.defer(recipient, campaign, reason, due, at)
        return skip(recipient, :campaign_expired, at) if due >= campaign.expires_at
        recipient.update!(deferral_reason: reason.to_s, delivery_due_at: due, skip_reason: nil)
      end

      def self.skip(recipient, reason, at)
        recipient.update!(status: "skipped", skip_reason: reason.to_s, deferral_reason: nil, delivery_due_at: nil, processed_at: at)
      end

      def self.fail_campaign(customer, campaign, reason, at)
        campaign.update!(status: "failed", failure_code: reason.to_s, finished_at: at, run_token: nil, run_lease_expires_at: nil)
        CloseRemaining.call(customer: customer, campaign: campaign, reason: :campaign_failed, at: at)
        RefreshStats.call(customer: customer, campaign: campaign, at: at)
      end

      def self.pending(customer, campaign)
        Sms::CampaignRecipient.where(customer_id: customer.id, campaign_id: campaign.id, status: "pending")
      end

      # The optional supplied clock is a floor, never proof that a lease stayed
      # valid while acquiring locks or processing a previous recipient.
      def self.current_time(at)
        [at, Time.current].max
      end

      def self.renew_lease(campaign, now)
        campaign.update!(heartbeat_at: now, run_lease_expires_at: now + Support::LEASE)
      end
      private_class_method :current_time, :renew_lease

      def self.empty(processed = 0)
        { processed_count: processed, has_more: false, next_run_at: nil }
      end
    end
  end
end
