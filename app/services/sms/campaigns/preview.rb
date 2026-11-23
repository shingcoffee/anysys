# frozen_string_literal: true

module Sms
  module Campaigns
    class Preview
      def self.call(customer:, actor:, campaign:, attributes: {}, contact_id: nil, at: Time.current)
        return Support.failure(:forbidden) unless Support.actor_allowed?(customer, actor)
        return Support.failure(:not_found) if campaign.persisted? && !Support.scoped?(customer, campaign)
        return Support.failure(:not_draft) unless campaign.status == "draft"
        contract, failure = DraftInput.build(customer: customer, campaign: campaign, attributes: attributes)
        return failure if failure
        draft = contract.model
        template = contract.template
        audience = Snapshot.audience(customer, contract.segment)
        relation = Sms::Audience::SegmentQuery.call(customer: customer, rules: audience["segment_rules"], field_specs: audience["field_specs"])
        return Support.failure(:audience_too_large) if relation.limit(Support::MAX_AUDIENCE + 1).count > Support::MAX_AUDIENCE
        selected = if contact_id.present?
          Sms::Contact.find_by(customer_id: customer.id, id: contact_id)
        end
        return Support.failure(:not_found) if contact_id.present? && !selected

        credential = begin
          Sms::CredentialResolver.call
        rescue Sms::Errors::CredentialsMissing
          nil
        end
        credential = nil unless credential&.configured?
        blockers = contract.complete_blockers
        blockers << :module_disabled unless Support.enabled?(customer)
        blockers << :credentials_missing unless credential
        blockers << :template_invalid if template && credential && template.provider_code(credential.provider).blank?
        start = Support.intended_start(draft, at)
        blockers << :schedule_in_past if draft.send_timing == "scheduled" && start && start <= at
        expiry = start && start + draft.deadline_hours.hours
        settings = draft.attributes.slice("frequency_window_hours")
        counts = Hash.new(0)
        deferred = Hash.new(0)
        matched = eligible = 0
        samples = []
        earliest = nil
        relation.find_in_batches(batch_size: Support::BATCH_SIZE) do |contacts|
          contacts.each do |contact|
            sample, due = sample_for(customer, contact, draft, template, settings, start || at, evaluated_at: at)
            matched += 1
            if sample[:eligible]
              eligible += 1
              deferred[:quiet_hours] += 1 if due > (start || at)
              earliest = due if earliest.nil? || due < earliest
            else
              counts[sample[:reason]] += 1
            end
            samples << sample if samples.size < (selected ? 4 : 5) && contact.id != selected&.id
          end
        end
        if selected
          sample, = sample_for(customer, selected, draft, template, settings, start || at, evaluated_at: at)
          unless relation.where(id: selected.id).exists?
            sample[:eligible] = false
            sample[:reason] = :outside_audience
          end
          samples.unshift(sample)
        end
        blockers << :audience_empty if eligible.zero?
        account_rate = credential && DispatchLimiter.rate_for(credential)
        if earliest && credential&.dispatch_next_at && earliest < credential.dispatch_next_at
          earliest = credential.dispatch_next_at
        end
        effective_rate = account_rate && [draft.send_rate_per_minute, account_rate * 60].min
        token = nil
        if campaign.persisted? && blockers.empty? &&
          ReviewToken.digest(draft.attributes.slice(*Contracts::Draft::FIELDS.map(&:to_s))) ==
          ReviewToken.digest(campaign.attributes.slice(*Contracts::Draft::FIELDS.map(&:to_s)))
          binding = ReviewToken.binding(customer: customer, campaign: campaign, template: Snapshot.template(template, credential),
            audience: audience, credential_id: credential.id, credential_mode: credential.mode, provider: credential.provider)
          token = ReviewToken.issue(binding, at: at)
        end
        Support.success(matched_count: matched, eligible_count: eligible, excluded_counts: counts.to_h,
          deferred_counts: deferred.to_h, samples: samples, intended_start_at: start, expires_at: expiry,
          earliest_dispatch_at: earliest, account_rate_per_second: account_rate, effective_rate_per_minute: effective_rate,
          estimated_minimum_duration_seconds: effective_rate && (eligible * 60 / effective_rate).ceil,
          blockers: blockers.uniq, evaluated_at: at, review_token: token)
      rescue Sms::Errors::TemplateVarsInvalid
        Support.failure(:account_rate_invalid)
      end

      def self.sample_for(customer, contact, draft, template, settings, at, evaluated_at: at)
        vars = if template && draft.variable_map.keys.sort == template.required_vars.sort
          VariableMap.resolve(map: draft.variable_map, snapshot: Snapshot.contact(contact), customer: customer, contact: contact)
        end
        decision = Eligibility.call(customer: customer, contact: contact, phone_e164: contact.phone_e164,
                                    vars: vars, settings: settings, at: evaluated_at)
        body = VariableMap.render(template&.body_template, vars)
        estimate = body && Sms::SegmentCalculator.call(text: body)
        zone = Schedule.valid_zone?(contact.timezone) ? contact.timezone : draft.timezone
        due = QuietWindow.next_allowed(at: at, timezone: zone, start_hour: draft.quiet_hours_start, end_hour: draft.quiet_hours_end)
        [{ contact_id: contact.id, name: contact.name, phone_e164: contact.phone_e164, vars: vars || {}, rendered_body: body,
           encoding: estimate&.fetch(:encoding), units: estimate&.fetch(:units), segments: estimate&.fetch(:segments),
           eligible: decision[:eligible], reason: decision[:reason] }, due]
      end
    end
  end
end
