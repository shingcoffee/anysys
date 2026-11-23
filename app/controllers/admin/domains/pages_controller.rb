# frozen_string_literal: true

module Admin
  module Domains
    # A domain's Forms tab: the forms bound to the domain's entities, plus the
    # unbound forms on the ungrouped domain. Fill in, preview, launch and
    # access control run from each row.
    class PagesController < ApplicationController
      include DomainBrowsing
      include PageListing

      def index
        load_domain_sections
        @section = find_domain_section(params[:domain_id])
        list_pages(
          Admin::Pages::BrowseScope.call(customer_id: current_customer.id,
                                         entity_ids: @section.entity_ids, unbound: @section.ungrouped?)
        )
      end
    end
  end
end
