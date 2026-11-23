# frozen_string_literal: true

module FeatureModules
  # Resolves a tenant's per-day send cap for a feature module from its
  # CustomerAssignment `configuration_json["daily_send_cap"]`, falling back to
  # `default` when the module is unassigned, the value is blank, or the value is
  # malformed. A non-numeric cap (e.g. "unlimited") would otherwise coerce to 0
  # and silently block ALL sends, so the malformed case logs which customer's
  # config is bad (never the value) and returns the safe default.
  #
  # Shared by Sms::Activities::Send and Emails::Activities::Send.
  module DailyCap
    module_function

    def for(customer:, module_key:, default:, log_label:)
      cfm = FeatureModules::CustomerAssignment.joins(:feature_module)
                                              .where(customer_id: customer.id, feature_modules: { key: module_key })
                                              .first
      return default unless cfm

      cap = cfm.configuration_json["daily_send_cap"]
      return default if cap.blank?

      Integer(cap)
    rescue ArgumentError, TypeError
      Rails.logger.warn(
        "#{log_label} customer #{customer.id} has a malformed daily_send_cap config; " \
        "falling back to the default cap (#{default})"
      )
      default
    end
  end
end
