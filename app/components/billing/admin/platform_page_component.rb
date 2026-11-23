# frozen_string_literal: true

module Billing
  module Admin
    # Page shell for every platform billing screen (Area d): the
    # Maintenance › Billing › <section> trail, the page header, and the
    # section tab strip, so nested show/new/edit pages keep the tabs too.
    #
    #   render Billing::Admin::PlatformPageComponent.new(
    #     customer_id: current_customer_id, section: :plans,
    #     crumbs: [{ label: @plan.name }], title: @plan.name, actions: [...]
    #   ) do ... end
    class PlatformPageComponent < ApplicationComponent
      SECTIONS = PlatformBillingNavComponent::TABS.to_h { |tab| [tab[:key], tab[:path_helper]] }.freeze

      def initialize(customer_id:, section:, title:, description: nil, crumbs: [], actions: [], badges: [],
                     section_path: nil, wrap_title: false)
        @customer_id = customer_id.to_s
        @section = section.to_sym
        @title, @description, @actions, @badges = title, description, actions, badges
        @crumbs = Array(crumbs)
        @section_path = section_path
        @wrap_title = wrap_title
      end

      def call
        render(AdminPageComponent.new(breadcrumbs: breadcrumbs, title: @title, description: @description,
                                      actions: @actions, badges: @badges, wrap_title: @wrap_title)) do
          safe_join([
            tag.div(render(PlatformBillingNavComponent.new(customer_id: @customer_id, current_path: helpers.request.path)), class: "mb-6"),
            content
          ])
        end
      end

      def breadcrumbs
        [
          { label: I18n.t("maint_platform.billing.breadcrumbs.maintenance"), path: helpers.admin_maintenance_path(@customer_id) },
          { label: I18n.t("maint_platform.billing.breadcrumbs.billing"), path: helpers.admin_maintenance_platform_billing_plans_path(@customer_id) },
          { label: I18n.t("comp_billing.nav.#{@section}"), path: (section_path if @crumbs.any?) }.compact,
          *@crumbs
        ]
      end

      private

      def section_path
        @section_path || helpers.public_send(SECTIONS.fetch(@section), @customer_id)
      end
    end
  end
end
