# frozen_string_literal: true

module FeatureModules
  # Sole owner of session[:feature_module_invocation]. Nothing else reads or
  # writes that key directly.
  class Invocation
    SESSION_KEY = :feature_module_invocation

    class << self
      # Session changes are not covered by ActiveRecord rollback. Couple them
      # to the submission Result so rejection/rollback preserves an earlier
      # invocation and never leaves an id pointing at a rolled-back entry.
      def with_submission(session:)
        previous = session[SESSION_KEY]&.deep_dup
        committed = false
        result = yield
        committed = result.success?
        result
      ensure
        unless committed
          previous.nil? ? session.delete(SESSION_KEY) : session[SESSION_KEY] = previous
        end
      end

      # +on_success+: record changes the module applies once it succeeds;
      # +audience+: who started it, which picks where the default exit lands.
      def begin!(session:, customer:, module_key:, triggering_page:, entity_entry:, input:, exit_target:,
                 on_success: nil, audience: nil)
        abandon!(session: session, reason: "superseded") if session[SESSION_KEY].present?

        feature_module = FeatureModules::Module.find_by(key: module_key)
        unless feature_module
          raise ModuleNotEnabled,
                I18n.t("feature_modules.errors.module_not_enabled", module_name: module_key)
        end

        unless feature_module.handoff_enabled?
          raise ModuleNotEnabled,
                I18n.t("feature_modules.errors.handoff_disabled", module_name: feature_module.display_name)
        end

        unless enabled_for?(customer, feature_module)
          raise ModuleNotEnabled,
                I18n.t("feature_modules.errors.module_not_enabled", module_name: feature_module.display_name)
        end

        registration = feature_module.registration_class
        # Coerce resolved values (form strings) to each field's declared type
        # BEFORE validating/persisting, so the contract sees typed values and
        # the module materializes typed values (e.g. integer amount, canonical
        # currency casing).
        casted_input = FeatureModules::InputCaster.call(
          input: input || {}, fields: registration.input_contract_fields
        )
        normalized_input = casted_input.transform_keys(&:to_s)

        contract = registration.input_contract_class.new(OpenStruct.new)
        unless contract.validate(normalized_input)
          blocking = contract.errors.to_hash.except(*deferred_inputs(registration, normalized_input))
          if blocking.any?
            raise InputContractViolation.new(
              I18n.t("feature_modules.errors.input_contract_violation",
                     module_name: feature_module.display_name,
                     details: blocking.keys.flat_map { |name| contract.errors.full_messages_for(name) }.join(", ")),
              contract_errors: blocking
            )
          end
        end

        entry_path = registration.entry_path_for(customer)
        if entry_path.blank?
          raise RegistrationError, I18n.t("feature_modules.errors.no_entry_path", module_key: feature_module.key)
        end

        session[SESSION_KEY] = {
          module_key:         feature_module.key,
          customer_id:        customer.id,
          triggering_page_id: triggering_page&.id,
          entity_entry_id:    entity_entry&.id,
          # Per-invocation secret. Modules that materialize a domain object
          # (e.g. Payments stamps it onto the Payment at charge time) can bind
          # completion to THIS invocation, not just to a shared idempotency key.
          token:              SecureRandom.hex(16),
          input:              casted_input.transform_keys(&:to_sym),
          # The end user still owes the user_fillable inputs; module entry points
          # stay closed (InvocationContext#require_module_invocation) until the
          # framework entry step (FeatureModules::HandoffsController) clears it.
          awaiting_input:     FeatureModules::HandoffCompletion.needs_completion?(registration),
          exit_target:        exit_target,
          on_success:         on_success.presence,
          audience:           audience.presence,
          started_at:         Time.current.iso8601
        }

        log!(
          feature_module: feature_module, customer: customer,
          action: "invocation.begin", status: :success,
          request_data: { input: casted_input, exit_target: exit_target }
        )

        entry_path
      end

      def current(session)
        data = session[SESSION_KEY]
        return nil if data.blank?

        # The session round-trips through the JSON cookie serializer, so a
        # value stashed with symbol keys comes back string-keyed on the next
        # request. Normalize to indifferent access so every consumer can read
        # it the same way regardless of when it was written.
        data = data.with_indifferent_access

        current_id = Current.customer&.id
        if current_id != data[:customer_id]
          raise CrossTenantViolation,
                I18n.t("feature_modules.errors.cross_tenant_violation")
        end

        data
      end

      def clear!(session)
        session.delete(SESSION_KEY)
      end

      # Overwrite the live invocation's resolved input (e.g. after the end user
      # completes user_fillable fields on the module entry page). No-ops when no
      # invocation is present; tenant-checked like #current. Keeps Invocation the
      # sole owner of SESSION_KEY.
      def update_input!(session:, input:)
        data = session[SESSION_KEY]
        return if data.blank?

        data = data.with_indifferent_access
        if Current.customer&.id != data[:customer_id]
          raise CrossTenantViolation,
                I18n.t("feature_modules.errors.cross_tenant_violation")
        end

        data[:input] = input.transform_keys(&:to_sym)
        data[:awaiting_input] = false
        session[SESSION_KEY] = data
        data
      end

      def abandon!(session:, reason:)
        data = session[SESSION_KEY]
        return if data.blank?

        data = data.with_indifferent_access
        fm = FeatureModules::Module.find_by(key: data[:module_key])
        if fm
          log!(
            feature_module: fm, customer: Current.customer,
            action: "invocation.abandon", status: :success,
            request_data: { reason: reason, invocation: data },
            response_data: { abandoned: true, reason: reason }
          )
        end

        clear!(session)
      end

      private

      # Blank user_fillable inputs do not block the handoff: the end user
      # supplies them on the entry step, where HandoffCompletion.complete!
      # validates the whole contract.
      def deferred_inputs(registration, normalized_input)
        registration.input_contract_fields
                    .select { |field| field.user_fillable? && normalized_input[field.name].blank? }
                    .map { |field| field.name.to_sym }
      end

      def enabled_for?(customer, feature_module)
        FeatureModules::CustomerAssignment.where(
          customer_id: customer.id,
          feature_module_id: feature_module.id,
          status: :active
        ).exists?
      end

      def log!(feature_module:, customer:, action:, status:, request_data:, response_data: nil)
        return if feature_module.nil?

        FeatureModules::Log.create!(
          feature_module: feature_module,
          customer_id:    customer&.id,
          action:         action,
          status:         status,
          request_data:   request_data.to_json,
          response_data:  response_data&.to_json
        )
      end
    end
  end
end
