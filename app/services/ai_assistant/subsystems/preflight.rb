# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # Checks a sub-system build against the workspace's plan limits and
    # settings before anything is written. A blocker stops the build; a
    # warning is reported and the build goes on.
    class Preflight
      # +entities+ / +pages+: rows the build will add, association bridges
      # included. +logins+: its person entity extends the person model.
      # +signup+: those people sign themselves up.
      Plan = Data.define(:entities, :pages, :logins, :signup) do
        def initialize(entities: 0, pages: 0, logins: false, signup: false) = super
      end
      Issue = Data.define(:code, :message)
      Result = Struct.new(:ok, :blockers, :warnings, keyword_init: true)

      def self.call(...) = new(...).call

      def initialize(customer:, plan:)
        @customer = customer
        @plan = plan
      end

      def call
        blockers = [quota_blocker("entity", @plan.entities), quota_blocker("page", @plan.pages), logins_blocker].compact
        Result.new(ok: blockers.empty?, blockers: blockers, warnings: [signup_warning].compact)
      end

      private

      def quota_blocker(item_key, needed)
        return if needed.zero? || quota.allow?(item_key, by: needed)

        Issue.new(code: "#{item_key}_quota",
                  message: I18n.t("ai_assistant.subsystems.preflight.quota_exceeded",
                                  needed: needed, unit: I18n.t("comp_billing.countable_items.#{item_key}.unit"),
                                  remaining: quota.remaining(item_key), limit: quota.limit(item_key)))
      end

      def logins_blocker
        return unless @plan.logins && EntityDefinitions::Capabilities.person_model(@customer.id).nil?

        Issue.new(code: "logins_unavailable", message: I18n.t("ai_assistant.subsystems.preflight.logins_unavailable"))
      end

      def signup_warning
        return unless @plan.logins && @plan.signup
        return if Authentication::Settings.for(@customer.id).signup_enabled?

        Issue.new(code: "signup_disabled", message: I18n.t("operations.journeys.sign_up_disabled"))
      end

      def quota = @quota ||= Billing::Quota.for(@customer)
    end
  end
end
