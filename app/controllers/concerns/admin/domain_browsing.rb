# frozen_string_literal: true

module Admin
  # Loads the customer's domain sections (Admin::Domains::Directory) for the
  # domain pages and opens the Domains sidebar, which lists every domain.
  module DomainBrowsing
    extend ActiveSupport::Concern

    included do
      dashboard_menu_item :entities
      before_action :expand_domains_sidebar
    end

    private

    def load_domain_sections
      @sections = Admin::Domains::Directory.call(customer_id: current_customer.id)
    end

    # :key is a domain id or "ungrouped"; nil picks the first section.
    def find_domain_section(key)
      return @sections.first if key.nil?

      @sections.find { |section| section.key == key } or raise ActiveRecord::RecordNotFound
    end

    def expand_domains_sidebar
      request.cookies.delete("sidebar_state_entities")
      cookies.delete("sidebar_state_entities", path: "/")
    end
  end
end
