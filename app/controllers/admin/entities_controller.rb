# frozen_string_literal: true

module Admin
  class EntitiesController < ApplicationController
    dashboard_menu_item :entities
    include Listable

    def show
      @entity = Entity.where(customer_id: current_customer.id).or(Entity.shared).find(params[:id])
      @setting = EntityIndexSetting.for(customer_id: current_customer.id, entity_id: @entity.id)

      if params[:per_page].present? || params[:density].present?
        @setting.write_list_prefs(per_page: params[:per_page], density: params[:density])
        @setting.save if @setting.has_changes_to_save?
      end

      @columns = columns_for([])
      @filters = Admin::Entities::FiltersBuilder.call(entity: @entity)
      @form_count = (form_count unless @entity.category_bridge?)
      per_page = EntityIndexSetting.clamp_per_page(params[:per_page].presence || @setting.per_page)
      @density = params[:density].presence || @setting.density || "comfortable"

      scope = EntityEntry.where(customer_id: current_customer.id, entity_id: @entity.id)
                         .order(created_at: :desc)
      if (link = ExtendedModels::Attributes.link(@entity.extended_model))
        scope = scope.includes(link.name)
      end

      respond_to do |format|
        format.html do
          @entry_count = scope.count
          result = listable(scope, columns: @columns, filters: @filters, per_page: per_page)
          @rows = result[:rows]
          @pagination = result[:pagination]
          @columns = columns_for(@rows)
        end
        format.csv do
          param_hash = params.to_unsafe_h.symbolize_keys.merge(page: 1, per_page: 100_000)
          result = ModuleEntriesResolver.call(
            scope: scope, columns: @columns, params: param_hash, filters: @filters,
            per_page: 100_000, max_per_page: 100_000
          )
          csv = Admin::Entities::EntriesCsv.call(rows: result[:rows], columns: columns_for(result[:rows]))
          filename = "#{@entity.name.to_s.parameterize}-entries-#{Date.current.strftime('%Y%m%d')}.csv"
          send_data csv, filename: filename, type: "text/csv"
        end
      end
    end

    private

    def form_count
      Admin::Pages::BrowseScope.call(customer_id: current_customer.id, entity_ids: [@entity.id]).count
    end

    # Sorting, search and filters read the columns' SQL, so the first build
    # needs no rows; cells read display text for the rows being rendered,
    # preloaded in one pass. customer_id is always the session tenant —
    # never params, never Current.
    def columns_for(rows)
      display = ::Entities::EntryDisplay.new(entity: @entity, entries: rows, customer_id: current_customer.id,
                                             audience: EntityAttributeAudience::ADMIN)
      Admin::Entities::ColumnsBuilder.call(entity: @entity, setting: @setting, customer_id: current_customer.id,
                                           display: display)
    end
  end
end
