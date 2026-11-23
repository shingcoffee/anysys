# frozen_string_literal: true

module FeatureModules
  # Controller concern for module pages. Exposes the live invocation read
  # from the session. All session access goes through FeatureModules::Invocation —
  # controllers never touch the session key directly.
  module InvocationContext
    extend ActiveSupport::Concern

    included do
      helper_method :current_invocation, :invocation_input if respond_to?(:helper_method)
    end

    def current_invocation
      FeatureModules::Invocation.current(session)
    end

    def invocation_input
      current_invocation&.dig(:input)
    end

    # Guard for a module's handoff entry point: the live invocation for
    # module_key, or nil after redirecting — home when there is none, back to
    # the framework entry step while the end user still owes user_fillable
    # inputs. Raises CrossTenantViolation like #current_invocation.
    def require_module_invocation(module_key, alert: t("feature_modules.handoff.no_active_request"))
      invocation = current_invocation
      if invocation.nil? || invocation[:module_key] != module_key.to_s
        redirect_to root_path, alert: alert
        return nil
      end

      if invocation[:awaiting_input]
        redirect_to feature_module_handoff_path(invocation[:customer_id])
        return nil
      end

      invocation
    end
  end
end
