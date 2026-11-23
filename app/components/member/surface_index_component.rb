# frozen_string_literal: true

module Member
  # High-level composer: renders a surface's index page.
  class SurfaceIndexComponent < ApplicationComponent
    def initialize(surface:, records:, page_meta:, customer:, row_action: nil)
      @surface    = surface
      @records    = records
      @page_meta  = page_meta
      @customer   = customer
      @row_action = row_action
    end

    attr_reader :surface, :records, :page_meta, :customer, :row_action

    def base_path
      "/#{customer.id}/member/#{surface.key}"
    end

    def row_path
      ->(record) { "/#{customer.id}/member/#{surface.key}/#{record.id}" }
    end
  end
end
