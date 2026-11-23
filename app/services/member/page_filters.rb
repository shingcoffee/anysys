# frozen_string_literal: true

module Member
  # Pagination helper. Returns [records, pagy] — the Pagy object carries all
  # the math PaginationComponent needs (page/limit/count/pages/from/to/prev/next).
  module PageFilters
    def self.paginate(scope, page:, per_page:)
      pagy    = Pagy.new(count: scope.count, page: [page.to_s.to_i, 1].max, limit: per_page.to_s.to_i)
      records = scope.limit(pagy.limit).offset(pagy.offset).to_a
      [records, pagy]
    end
  end
end
