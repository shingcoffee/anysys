# frozen_string_literal: true

module Admin
  module Maintenance
    # JSON options for `reference` fields on the flowchart step form.
    # Authorization is the same as FlowchartTracesController: ApplicationController
    # concerns (RouteAuthorization + FlowchartVisibility) gate this as owner-only;
    # Current.customer is the URL tenant (platform prefix → 81721200).
    class FlowchartReferenceOptionsController < ApplicationController
      dashboard_menu_item :maintenance

      QUERY_MAX_LENGTH = 100
      OPTIONS_LIMIT = 50

      def show
        return head :not_acceptable unless request.format.json?

        source = CodeGenerators::ReferenceSources.fetch(params[:source].to_s)
        return unknown_source_response unless source

        options = source.options(
          customer: current_customer,
          query: query_param,
          limit: OPTIONS_LIMIT,
          entity_id: entity_id_param,
          exclude_id: exclude_id_param
        )

        render json: { options: options }
      end

      private

      def query_param
        raw = params[:q]
        return unless raw.is_a?(String)

        trimmed = raw.strip
        return if trimmed.empty?

        trimmed[0, QUERY_MAX_LENGTH]
      end

      def entity_id_param
        raw = params[:entity_id]
        return if raw.blank?
        return unless raw.is_a?(String) || raw.is_a?(Numeric)

        Integer(raw, exception: false)
      end

      def exclude_id_param
        raw = params[:exclude_id]
        return if raw.blank?
        return unless raw.is_a?(String) || raw.is_a?(Numeric)

        Integer(raw, exception: false)
      end

      def unknown_source_response
        render json: { error: t("maint_core.flowcharts.reference_options.unknown_source") },
               status: :not_found
      end
    end
  end
end
