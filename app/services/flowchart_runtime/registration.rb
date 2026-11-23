# frozen_string_literal: true

module FlowchartRuntime
  # Public-only member registration for the register_member step. Lookups use
  # the shared normalized-email finder so a taken address never creates a user.
  # Browser-visible success is the same for :created and :existing.
  module Registration
    module_function

    def call(ctx, person:, identity: nil)
      return Step.fail(ctx, :"register_member.public_only") unless public_audience?(ctx)
      return Step.fail(ctx, :"register_member.person_entity_required") unless person_entity?(ctx)

      customer_id = ctx && ctx[:customer_id]
      return Step.fail(ctx, :"register_member.signup_disabled") unless signup_allowed?(customer_id)

      identity = identity_from(ctx, identity)
      messages = identity_error_messages(identity, customer_id)
      return reject_invalid(ctx, messages) if messages.any?

      ctx[:uniform_timing_started_at] = ::Authentication::UniformTiming.start
      existing = ::Authentication::User.find_by_normalized_email(identity["email"])
      if existing
        record_existing!(ctx, existing, customer_id)
        assign_outcome(ctx)
        ctx[:discard_record] = true
        return { "status" => "existing" }
      end

      register_new!(ctx, person, identity, customer_id)
    end

    def public_audience?(ctx)
      ctx && ctx[:audience].to_s == EntityAttributeAudience::PUBLIC
    end
    private_class_method :public_audience?

    def person_entity?(ctx)
      entity = ctx && ctx[:bound_entity]
      entity.respond_to?(:person?) && entity.person?
    end
    private_class_method :person_entity?

    def signup_allowed?(customer_id)
      FeatureModules::Module.enabled?(key: "authentication", customer_id: customer_id) &&
        ::Authentication::Settings.for(customer_id).signup_enabled?
    end
    private_class_method :signup_allowed?

    def identity_from(ctx, identity)
      raw = identity
      raw = (ctx && (ctx[:identity] || ctx["identity"])) if raw.nil?
      raw ||= {}
      raw = raw.respond_to?(:to_h) ? raw.to_h.stringify_keys : {}
      People::IDENTITY_KEYS.index_with { |key| raw[key].to_s }
    end
    private_class_method :identity_from

    # Presence/format only. Uniqueness (:taken) is ignored so a live address
    # never fails here — that branch is :existing after the shared lookup.
    def identity_error_messages(identity, customer_id)
      probe = ::Authentication::User.new(
        first_name: identity["first_name"],
        last_name: identity["last_name"],
        email: identity["email"],
        customer_id: customer_id
      )
      probe.allow_blank_password = true
      return [] if probe.valid?

      probe.errors.delete(:email, :taken)
      return [] if probe.errors.empty?

      probe.errors.full_messages
    end
    private_class_method :identity_error_messages

    def reject_invalid(ctx, messages)
      ctx[:errors] ||= []
      Array(messages).each do |message|
        text = message.to_s
        ctx[:errors] << text unless ctx[:errors].include?(text)
      end
      ctx[:error_details] ||= []
      ctx[:error_details] << { "code" => "record_invalid", "field" => nil, "details" => {} }
      false
    end
    private_class_method :reject_invalid

    # An unconfirmed member's own confirmation is still pending (with its
    # claim); a repeat submission leaves both alone. A flood-throttled link
    # still records the continuation for the member's next sign-in.
    def record_existing!(ctx, user, customer_id)
      return unless ::Authentication::NotifyExistingMember.member_of?(user, customer_id)

      ::Authentication::NotifyExistingMember.call(user: user, customer_id: customer_id)
      People::Claim.record!(
        user: user,
        entry: nil,
        continuation: continuation_from(ctx),
        created_user: false
      )
    end
    private_class_method :record_existing!

    def register_new!(ctx, person, identity, customer_id)
      customer = Customer.find_by(id: customer_id)
      return Step.fail(ctx, :"register_member.unavailable") unless customer

      result = ::Authentication::RegisterMember.call(
        customer: customer,
        attributes: identity,
        passwordless: true
      )
      return quota_exhausted(ctx, customer_id) if result.status == :quota_exceeded
      return reject_invalid(ctx, result.errors.full_messages) if result.status != :created

      entry = persist_person(ctx, person, identity)
      return false unless entry

      People::Claim.record!(
        user: result.user,
        entry: entry,
        continuation: continuation_from(ctx),
        created_user: true
      )
      assign_outcome(ctx)
      { "status" => "created" }
    end
    private_class_method :register_new!

    # Answers like a taken address so a full quota never tells a visitor which
    # emails already have accounts.
    def quota_exhausted(ctx, customer_id)
      Rails.logger.warn("[register_member] member quota exhausted for customer #{customer_id}")
      assign_outcome(ctx)
      ctx[:discard_record] = true
      { "status" => "existing" }
    end
    private_class_method :quota_exhausted

    def persist_person(ctx, person, identity)
      entry = person_entry(ctx, person)
      return false unless entry

      data = entry.data_json
      data = data.is_a?(Hash) ? data.stringify_keys : {}
      People::IDENTITY_KEYS.each { |key| data[key] = identity[key].to_s }
      entry.data_json = data
      entry.user_id = nil
      return false unless Entries.save(ctx, entry)

      entry
    end
    private_class_method :persist_person

    def person_entry(ctx, person)
      entity = ctx && ctx[:bound_entity]
      if person.is_a?(EntityEntry) &&
         person.customer_id.to_s == ctx[:customer_id].to_s &&
         (person.entity_id.blank? || person.entity_id == entity&.id)
        person.entity_id = entity.id if person.entity_id.blank? && entity
        return person
      end

      Entries.scope(ctx).new(customer_id: ctx[:customer_id])
    end
    private_class_method :person_entry

    def continuation_from(ctx)
      raw = ctx && (ctx[:continuation] || ctx["continuation"])
      return nil if raw.nil?
      return nil unless raw.respond_to?(:to_h)

      hash = raw.to_h.stringify_keys
      return nil if hash.empty?

      prefill = hash["prefill"]
      {
        "action_key" => hash["action_key"],
        "prefill" => prefill.respond_to?(:to_h) ? prefill.to_h.stringify_keys : {}
      }
    end
    private_class_method :continuation_from

    def assign_outcome(ctx)
      raw = ctx[:submission_outcome] || ctx["submission_outcome"]
      if raw.is_a?(Hash)
        outcome = raw.stringify_keys
        return if outcome["preset"].present?

        outcome["preset"] = "registration_pending"
        ctx[:submission_outcome] = outcome
      else
        ctx[:submission_outcome] = { "preset" => "registration_pending" }
      end
    end
    private_class_method :assign_outcome
  end
end
