# frozen_string_literal: true

module Admin
  # The forms list shared by the domain and entity Forms tabs: search, the
  # Live / Draft filter, sorting, pagination and form health badges over an
  # Admin::Pages::BrowseScope relation.
  module PageListing
    extend ActiveSupport::Concern

    LIST_PARAMS = %i[q sort dir page per_page launched].freeze

    included do
      helper_method :page_list_params
    end

    private

    def list_pages(scope)
      @columns = Admin::Pages::ColumnsBuilder.call
      @filters = [launch_filter]
      result = ModuleEntriesResolver.call(scope: scope, columns: @columns, filters: @filters, params: page_list_params)
      @rows = result[:rows]
      @pagination = result[:pagination]
      @form_statuses = ::Pages::FormHealth.for(@rows)
    end

    def page_list_params
      params.permit(*LIST_PARAMS).to_h.symbolize_keys
    end

    def launch_filter
      {
        key: :launched,
        label: t("admin_misc.pages.filters.launch_label"),
        options: [
          [t("admin_misc.pages.filters.launched_option"), "true"],
          [t("admin_misc.pages.filters.not_launched_option"), "false"]
        ],
        scope: ->(rel, val) { rel.where(launched: ActiveRecord::Type::Boolean.new.cast(val)) }
      }
    end
  end
end
