# frozen_string_literal: true

module Admin
  # Shows one domain at a time: its header and totals. The index shows the
  # first domain, `show` the domain picked in the sidebar (:id is a domain id
  # or "ungrouped"), which lists each domain's record types. Domains are
  # read-only here; the platform owner manages them under maintenance.
  class DomainsController < ApplicationController
    include DomainBrowsing

    before_action :load_domain_sections

    def index
      @section = find_domain_section(nil)
    end

    def show
      @section = find_domain_section(params[:id])
      render :index
    end
  end
end
