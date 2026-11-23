# frozen_string_literal: true

module FlowchartRuntime
  # Asks for a page → module handoff after the submission commits: parks
  # { module_key, input } on ctx[:submission_outcome]["handoff"], which
  # FeatureModules::PageHandoff begins once the record is saved. The module
  # validates and casts the input against its own contract at that point.
  module Handoff
    # Step actions that end the submission in a module instead of the page.
    ACTIONS = %w[hand_off_to_module request_payment].freeze

    module_function

    def request(ctx, module_key:, input: {}, exit_target: nil)
      key = module_key.to_s.strip
      return Step.fail(ctx, :"hand_off_to_module.module_unavailable") unless available?(key, ctx && ctx[:customer_id])

      write(ctx, module_key: key, input: input.to_h.transform_keys(&:to_s), exit_target: exit_target)
      true
    end

    def available?(module_key, customer_id)
      return false if module_key.blank? || customer_id.blank?

      feature = FeatureModules::Module.find_by(key: module_key)
      return false unless feature&.handoff_enabled?

      FeatureModules::Module.enabled?(key: module_key, customer_id: customer_id)
    end

    # +on_success+: record changes the module applies once it succeeds (see
    # FlowchartRuntime::Payments.request).
    def write(ctx, module_key:, input:, exit_target: nil, on_success: nil)
      outcome = (ctx[:submission_outcome] || {}).to_h.stringify_keys
      payload = { "module_key" => module_key, "input" => input }
      target = stringify_exit(exit_target)
      payload["exit_target"] = target if target
      payload["on_success"] = on_success if on_success.present?
      outcome["handoff"] = payload
      ctx[:submission_outcome] = outcome
    end

    def stringify_exit(exit_target)
      return nil if exit_target.nil?

      hash = exit_target.respond_to?(:to_h) ? exit_target.to_h.stringify_keys : nil
      return nil if hash.blank? || hash["kind"].to_s.strip.empty?

      hash
    end
    private_class_method :stringify_exit
  end
end
