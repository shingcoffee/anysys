# frozen_string_literal: true

module Admin
  module Maintenance
    # Renders a built page exactly as the admin audience sees it
    # (dashboard layout). Linked from the page detail "Rendered Views" card.
    class PageRendersController < ApplicationController
      include PageRendering
      include SharedResourceMode

      dashboard_menu_item :maintenance

      def show
        @page = definition_scope(Page).find(params[:page_id])
        raise ActiveRecord::RecordNotFound unless @page.launched? && @page.visible_to?(:admin)

        prepare_page_render(@page, quick_add_depth: 0)
      end
    end
  end
end
