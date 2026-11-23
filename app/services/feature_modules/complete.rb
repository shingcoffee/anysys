# frozen_string_literal: true

module FeatureModules
  # Orchestrates module-flow completion:
  # 1. Read invocation from session (tenant-checked).
  # 2. Validate output against the module's output_contract.
  # 3. Resolve exit URL via ExitResolver (with fallback chain).
  # 4. Write audit log.
  # 5. Clear session.
  # 6. Return { redirect_to:, flash: }.
  #
  # Raises OutputContractViolation on invalid output.
  # Raises CrossTenantViolation if session customer_id doesn't match Current.
  class Complete
    def self.call(session:, customer:, module_key:, output:)
      new(session: session, customer: customer, module_key: module_key, output: output).call
    end

    def initialize(session:, customer:, module_key:, output:)
      @session    = session
      @customer   = customer
      @module_key = module_key
      @output     = output || {}
    end

    def call
      invocation = load_invocation
      validate_output!
      redirect_url = resolve_redirect(invocation)
      write_success_log(invocation: invocation, redirect_url: redirect_url)
      Invocation.clear!(@session)

      {
        redirect_to: redirect_url,
        flash:       { feature_module_result: { module_key: @module_key, output: @output } }
      }
    end

    private

    def feature_module
      @feature_module ||= FeatureModules::Module.find_by(key: @module_key)
    end

    def registration
      @registration ||= feature_module&.registration_class || FeatureModules::Module::NullRegistration
    end

    def load_invocation
      Invocation.current(@session)
    rescue CrossTenantViolation => e
      write_log(status: :failure, response_data: { cross_tenant: true })
      Invocation.clear!(@session)
      raise e
    end

    def validate_output!
      contract = registration.output_contract_class.new(OpenStruct.new)
      normalized = @output.transform_keys(&:to_s)

      return if contract.validate(normalized)

      details = contract.errors.full_messages.join(", ")
      write_log(status: :failure, response_data: { error: details, output: @output })
      raise OutputContractViolation.new(
        I18n.t("feature_modules.errors.output_contract_violation",
               module_name: feature_module&.name || @module_key),
        contract_errors: contract.errors.to_hash
      )
    end

    def resolve_redirect(invocation)
      ExitResolver.call(
        customer:            @customer,
        module_key:          @module_key,
        session_exit_target: invocation&.dig(:exit_target),
        audience:            invocation&.dig(:audience)
      )
    end

    def write_success_log(invocation:, redirect_url:)
      response_data = { redirect_to: redirect_url }
      response_data[:stale] = true if invocation.blank?
      write_log(status: :success, response_data: response_data)
    end

    def write_log(status:, response_data:)
      return unless feature_module
      FeatureModules::Log.create!(
        feature_module: feature_module,
        customer_id:    @customer.id,
        action:         "invocation.complete",
        status:         status,
        request_data:   { output: @output }.to_json,
        response_data:  response_data.to_json
      )
    end
  end
end
