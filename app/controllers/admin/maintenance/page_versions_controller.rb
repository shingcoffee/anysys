# frozen_string_literal: true

module Admin
  module Maintenance
    # Version history for a page. All actions are scoped through the page, which
    # is itself tenant-scoped (`Page.for_current_customer`), so versions of
    # another customer's page are unreachable (404).
    class PageVersionsController < BaseVersionsController
      versioned_resource finder: -> { definition_scope(Page).find(params[:page_id]) },
                         ivar: :@page

      # GET .../versions/:id/edit — redirect to the page editor for this version.
      def edit
        version = line_version
        redirect_to edit_admin_maintenance_page_path(current_customer_id, @page, version: version.id)
      end
    end
  end
end
