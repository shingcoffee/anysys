# frozen_string_literal: true

module Listable
  extend ActiveSupport::Concern

  DEFAULT_PER_PAGE = ModuleEntriesResolver::DEFAULT_PER_PAGE

  def listable(scope, columns:, filters: [], per_page: DEFAULT_PER_PAGE)
    param_hash = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h.symbolize_keys : params.to_h.symbolize_keys
    # ModuleEntriesResolver prefers params[:per_page] over the keyword. Stamp
    # the caller-clamped value so a crafted query cannot bypass the cap.
    param_hash[:per_page] = per_page
    ModuleEntriesResolver.call(
      scope: scope,
      columns: columns,
      params: param_hash,
      filters: filters,
      per_page: per_page
    )
  end
end
