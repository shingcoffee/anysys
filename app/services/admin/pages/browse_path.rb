# frozen_string_literal: true

module Admin
  module Pages
    # Where a page is listed in the Domains area: its bound entity's Forms
    # tab, or the ungrouped domain's Forms tab when the page is unbound (no
    # entity, a bridge entity, or one that no longer exists), matching how
    # BrowseScope classifies it.
    class BrowsePath
      Crumb = Data.define(:label, :path)

      def self.for(page, customer_id:) = new(page, customer_id: customer_id).path

      def initialize(page, customer_id:)
        @page = page
        @customer_id = customer_id
      end

      def path
        helpers = Rails.application.routes.url_helpers
        return helpers.admin_entity_pages_path(@customer_id, entity) if entity

        helpers.admin_domain_pages_path(@customer_id, ::Admin::Domains::Directory::UNGROUPED)
      end

      # The breadcrumb naming the list `path` points at.
      def crumb
        label = entity ? entity.display_label : I18n.t("chrome.sidebar.entities.ungrouped")
        Crumb.new(label: label, path: path)
      end

      private

      def entity
        return @entity if defined?(@entity)

        bound = @page.entity
        @entity = bound if bound && !bound.category_bridge?
      end
    end
  end
end
