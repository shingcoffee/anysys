# frozen_string_literal: true

module Admin
  module Pages
    # Right-side slide-over for admin page ops: preview + DistributionCard
    # (launch / visibility). Loaded into turbo-frame `page-publishing`.
    class PublishingPanelComponent < ViewComponent::Base
      FRAME_ID = "page-publishing"

      def initialize(page:, customer_id:, return_to:, close_path:)
        @page        = page
        @customer_id = customer_id
        @return_to   = return_to
        @close_path  = close_path
      end

      def title
        page.name
      end

      def preview_path
        helpers.admin_maintenance_page_preview_path(customer_id, page)
      end

      private

      attr_reader :page, :customer_id, :return_to, :close_path
    end
  end
end
