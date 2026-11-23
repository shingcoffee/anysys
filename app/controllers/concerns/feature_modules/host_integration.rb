# frozen_string_literal: true

module FeatureModules
  # Generic host-integration concern included in ApplicationController.
  #
  # For every request, iterates modules enabled for the current customer
  # and invokes Registration.before_request(self). Any module may redirect
  # or halt via the controller; if the response is already a redirect,
  # remaining modules are skipped.
  #
  # Exposes the generic feature_module_enabled?(key) helper to views.
  #
  # Adding a new cross-cutting module: override .before_request in the
  # module's Registration — no changes needed here.
  #
  # Iteration order is unspecified — modules MUST NOT rely on running before
  # or after any other module. If deterministic ordering becomes necessary,
  # introduce an explicit `priority` column on feature_modules.
  module HostIntegration
    extend ActiveSupport::Concern

    included do
      before_action :run_feature_module_before_request

      helper_method :feature_module_enabled?
    end

    # View/controller helper — generic enablement check.
    def feature_module_enabled?(key)
      return false if current_customer_id.blank?

      FeatureModules::Module.enabled?(key: key, customer_id: current_customer_id)
    end

    private

    def run_feature_module_before_request
      return if current_customer_id.blank?

      FeatureModules::Module.enabled_for_customer(current_customer_id).each do |fm|
        fm.registration_class.before_request(self)
        return if performed?
      end
    end
  end
end
