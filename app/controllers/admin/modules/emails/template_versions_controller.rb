# frozen_string_literal: true

module Admin
  module Modules
    module Emails
      # Version history for an email template. All actions are scoped through
      # the template, which is itself tenant-scoped (`Template.for_current_customer`),
      # so versions of another customer's template are unreachable (404).
      class TemplateVersionsController < Admin::Maintenance::BaseVersionsController
        dashboard_menu_item :modules

        versioned_resource finder: -> { ::Emails::Template.for_current_customer.find(params[:template_id]) },
                            ivar: :@template

        # GET .../versions/:id/edit — redirect to the template editor for this version.
        def edit
          version = @template.template_versions.find(params[:id])
          redirect_to edit_admin_modules_emails_template_path(current_customer_id, @template, version: version.id)
        end

        private

        def guard_write!
          return if FeatureModules::Module.enabled?(key: "email", customer_id: current_customer.id)

          head :not_found
        end
      end
    end
  end
end
