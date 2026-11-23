# frozen_string_literal: true

module Admin
  module Maintenance
    # Full server-rendered preview of a layout template by key, with no entity
    # required — used by the "Preview" button when creating a not-yet-saved entity.
    class TemplatePreviewsController < ApplicationController
      dashboard_menu_item :maintenance

      def show
        template = PageLayoutTemplates.find(params[:id])

        if template.nil?
          redirect_to admin_maintenance_entities_path(current_customer_id), alert: t("maint_core.flash.template_previews.not_found")
          return
        end

        built = TemplatePreviewBuilder.call(customer: current_customer, ref_data: template)
        @page = built[:page]
        @content = built[:content]
        @form_action = "#"

        render template: "admin/maintenance/pages/preview", layout: "template_preview"
      end
    end
  end
end
