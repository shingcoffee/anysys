# frozen_string_literal: true

module Billing
  module Admin
    # Renders the new/edit form for a billing plan (platform owner, Area d).
    #
    # Constructor:
    #   plan:        Billing::Plan instance (new or persisted)
    #   customer_id: current customer_id (owner's) for route helpers
    class PlanFormComponent < ApplicationComponent
      include Presentation

      def initialize(plan:, customer_id:, items: [], form: nil)
        @plan        = plan
        @customer_id = customer_id.to_s
        @items       = items
        @form        = form || Billing::Contracts::Plan.new(plan)
      end

      attr_reader :plan, :customer_id, :items
      attr_reader :form
      def form_record = plan
      def form_scope = "billing_plan"

      # Always render prices with two decimals (e.g. "29.00"), since a number
      # input would otherwise drop the trailing zero from the BigDecimal value.
      def amount_usd_value = price_input_value(:amount_usd)
      def amount_cny_value = price_input_value(:amount_cny)

      def price_input_value(field)
        value = form_value(field)
        value.is_a?(Numeric) ? format("%.2f", value) : value
      end

      # Blank is unlimited. Keep invalid text so a rejected create can be corrected.
      def limit_input_value(item)
        raw = fact(form_value(:limits), item.key)
        return if raw.nil? || raw.to_s.strip.blank?
        text = raw.to_s.strip
        return if text.casecmp("unlimited").zero? || text.match?(/\A-\d+\z/)

        raw
      end

      def form_url
        if plan.persisted?
          helpers.admin_maintenance_platform_billing_plan_path(customer_id, plan)
        else
          helpers.admin_maintenance_platform_billing_plans_path(customer_id)
        end
      end

      def form_method
        plan.persisted? ? :patch : :post
      end

      def index_path
        helpers.admin_maintenance_platform_billing_plans_path(customer_id)
      end

      def interval_options
        submitted_options(Billing::Plan::INTERVALS.map { |interval| [I18n.t("comp_billing.plan_form.intervals.#{interval}"), interval] }, :interval)
      end

      # Unit suffix for a limit input (e.g. "emails"). Blank/missing stays hidden.
      def item_unit(item)
        return unless item.respond_to?(:unit)

        item.unit.to_s.strip.presence
      end
    end
  end
end
