# frozen_string_literal: true

require "timeout"

module Admin
  module Maintenance
    class FlowchartTracesController < ApplicationController
      dashboard_menu_item :maintenance
      before_action :find_flowchart

      # Captured SQL text beyond this length is clamped before rendering.
      MAX_SQL_LENGTH = 4000

      def create
        subject = trace_subject
        return if performed?

        input = trace_params.to_h.deep_symbolize_keys.merge(runtime_context_for(subject))
        result = nil
        ActiveRecord::Base.transaction(requires_new: true) do
          result = ActivityTracer.new(subject).call(input)
          raise ActiveRecord::Rollback
        end

        render json: {
          success: result.success?,
          signal: result.signal&.to_h&.dig(:semantic)&.to_s,
          trace: result.trace,
          trace_nodes: result.trace_nodes,
          queries: truncated_queries(result.queries),
          context: ActivityTracer.redact_sensitive_keys(ContextSanitizer.sanitize(result.ctx)),
          errors: collected_trace_errors(result.ctx),
          error: result.error,
          timeout: result.timeout?,
          trace_truncated: result.truncated == true
        }
      end

      private

      def collected_trace_errors(ctx)
        return [] unless ctx.is_a?(Hash)

        Array(ctx[:errors]).select { |msg| msg.is_a?(String) && msg.present? }.uniq
      end

      # Queries arrive as {sql:, duration_ms:, name:} hashes from
      # FlowchartRuntime::QueryLogger; only the SQL text needs clamping.
      def truncated_queries(queries)
        Array(queries).map do |query|
          query = query.symbolize_keys
          sql = query[:sql].to_s
          sql = "#{sql[0, MAX_SQL_LENGTH]}#{t("maint_core.flowcharts.editor.sql_truncated_suffix")}" if sql.length > MAX_SQL_LENGTH

          { sql: sql, duration_ms: query[:duration_ms], name: query[:name] }
        end
      end

      def find_flowchart
        @flowchart = Flowchart.accessible.find(params[:flowchart_id])
      end

      def trace_params
        params.permit(:flowchart_id, input: {})[:input] || {}
      end

      # The request keys of Pages::Submission::Context; the entity is the one
      # the flowchart's pages share (Flowcharts::DesignEntity), and the run
      # starts from a new record of it, as a create submit does. Merged after
      # the posted input so a tester cannot inject bound_entity / customer_id /
      # authentication (or the other runtime metadata) through the JSON body.
      def runtime_context_for(_record)
        entity = ::Flowcharts::DesignEntity.for(@flowchart, customer_id: shared_resources_mode? ? nil : current_customer_id)
        record = entity && EntityEntry.build_for(entity).new(entity: entity, customer_id: current_customer_id)
        {
          bound_entity: entity,
          model: record,
          page_record: record,
          customer_id: current_customer_id,
          authentication: FlowchartRuntime::Authentication.from_request(request),
          current_user_id: current_user&.id,
          current_user_role: current_user&.primary_role_key,
          audience: EntityAttributeAudience.for_user(current_user, customer_id: current_customer_id),
          device_type: ::Pages::DeviceType.call(request.user_agent),
          request_ip: request.remote_ip,
          user_agent: request.user_agent,
          locale: I18n.locale.to_s,
          request_id: request.request_id
        }
      end

      # In-memory preview of an unsaved canvas graph. Never persist a version
      # or overwrite the stored configuration / activity columns.
      #
      # Do not call Flowchart#generate_activity — on a tenant-prefix shared
      # flowchart it no-ops via `return if override_customer_id.present?` and
      # ActivityTracer would execute the dup'd persisted artifact. Compile
      # with ActivityGenerator directly, then keep the preview in :draft so
      # ActivityTracer wraps it as RuntimeFlowchart(preview: true) and the
      # posted configuration wins.
      def trace_subject
        raw = params[:configuration]
        return @flowchart if raw.blank?

        config = posted_configuration(raw)
        return invalid_configuration_response unless preview_configuration?(config)
        return payload_too_large_response if payload_too_large?(config)

        preview = @flowchart.dup
        preview.configuration_json = config
        preview.status = :draft
        begin
          Timeout.timeout(FlowchartServerValidator::DRY_RUN_TIMEOUT_SECONDS) do
            preview.activity = ActivityGenerator.new(preview).generate
          end
        rescue Timeout::Error
          return codegen_timeout_response
        end
        preview
      end

      def posted_configuration(raw)
        parsed = case raw
        when String then JSON.parse(raw)
        when ActionController::Parameters then raw.to_unsafe_h
        else raw
        end
        parsed.respond_to?(:deep_stringify_keys) ? parsed.deep_stringify_keys : parsed
      rescue JSON::ParserError
        nil
      end

      def preview_configuration?(config)
        config.is_a?(Hash) && config["elements"].is_a?(Array)
      end

      def payload_too_large?(config)
        Array(config["elements"]).size > FlowchartServerValidator::MAX_ELEMENTS ||
          Array(config["connections"]).size > FlowchartServerValidator::MAX_CONNECTIONS
      end

      def invalid_configuration_response
        render json: { error: t("maint_core.errors.page_templates.invalid_configuration") },
               status: :unprocessable_entity
      end

      def payload_too_large_response
        render json: { error: t("maint_core.flowcharts.editor.server_check_unavailable") },
               status: :unprocessable_entity
      end

      def codegen_timeout_response
        render json: { error: t("maint_core.flowcharts.editor.server_check_unavailable") },
               status: :unprocessable_entity
      end
    end
  end
end
