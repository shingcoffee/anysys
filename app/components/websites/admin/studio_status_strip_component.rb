# frozen_string_literal: true

module Websites
  module Admin
    # Compact studio summary above the pages table: live state, public URL, count.
    class StudioStatusStripComponent < ApplicationComponent
      def initialize(website:, customer_id:, page_count: 0)
        @website = website
        @customer_id = customer_id
        @page_count = page_count.to_i
      end

      def published?
        ActiveModel::Type::Boolean.new.cast(@website.try(:published))
      end

      def public_path
        helpers.page_shortcuts_mounted_path(PageShortcuts::PublicPath.website_home(customer_id: @customer_id, host: helpers.request.host))
      end

      def page_count_label
        t("website.admin.pages.index.page_count", count: @page_count)
      end

      def status_label
        published? ? t("website.admin.pages.index.site_live") : t("website.admin.pages.index.site_unpublished")
      end
    end
  end
end
