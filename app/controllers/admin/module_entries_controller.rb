# frozen_string_literal: true

module Admin
  class ModuleEntriesController < ApplicationController
    dashboard_menu_item :modules

    def show
      module_key = resolve_module_key(params[:module_key])
      unless FeatureModules::Module.enabled?(key: module_key, customer_id: current_customer.id)
        return head :not_found
      end

      registration = FeatureModules::Module.find_by!(key: module_key).registration_class
      filter_params = params.permit(:q, :sort, :dir, :page, :per_page).to_h.symbolize_keys
      result = begin
        registration.entries_for(entry_key: params[:key], params: filter_params)
      rescue ArgumentError, NotImplementedError
        return head :not_found
      end

      resolved = ModuleEntriesResolver.call(
        scope: result[:scope], columns: result[:columns], params: filter_params
      )

      @title = result[:title] || params[:key].humanize
      @module_key = module_key
      @columns = result[:columns]
      @rows = resolved[:rows]
      @pagination = resolved[:pagination]
      @row_path = result[:row_path]
    end

    private

    # URL segment is the plural module path (e.g. "payments"), but the
    # FeatureModules::Module registry key may be singular (e.g. "payment"). Try the
    # incoming segment first, then its singular form.
    def resolve_module_key(segment)
      return segment if FeatureModules::Module.exists?(key: segment)

      singular = segment.to_s.singularize
      FeatureModules::Module.exists?(key: singular) ? singular : segment
    end
  end
end
