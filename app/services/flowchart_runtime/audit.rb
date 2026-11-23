# frozen_string_literal: true

module FlowchartRuntime
  # Structured audit log line and tenant-scoped flowchart_audit_events row for
  # the audit_log step. The insert joins the run's transaction, so a rolled-back
  # submission leaves no row.
  module Audit
    class Error < StandardError; end

    SEVERITIES = %w[debug info warn error critical].freeze
    OUTCOMES = %w[success failure].freeze
    LOGGER_METHOD = {
      "debug" => "debug",
      "info" => "info",
      "warn" => "warn",
      "error" => "error",
      "critical" => "error"
    }.freeze

    module_function

    def write(ctx, event_type:, resource_type: nil, resource_id: nil, actor_id: nil,
              actor_type: nil, metadata: {}, ip_address: nil, user_agent: nil,
              severity: "info", outcome: "success", changes: nil)
      actor_id = presence(actor_id) || (ctx && ctx[:current_user_id])
      actor_type = presence(actor_type) || (actor_id.present? ? "User" : nil)
      resource_id = presence(resource_id) || default_resource_id(ctx)
      resource_type = presence(resource_type) || default_resource_type(ctx)
      ip_address = presence(ip_address) || (ctx && ctx[:request_ip])
      user_agent = presence(user_agent) || (ctx && ctx[:user_agent])
      level = SEVERITIES.include?(severity.to_s) ? severity.to_s : "info"
      meta = metadata.is_a?(Hash) ? metadata.dup : {}
      meta = meta.stringify_keys if meta.respond_to?(:stringify_keys)
      result = OUTCOMES.include?(outcome.to_s) ? outcome.to_s : "success"
      meta["outcome"] = result
      meta["changes"] = changes unless changes.nil?
      customer_id = ctx && ctx[:customer_id]
      entry = {
        event_type: event_type.to_s,
        resource_type: resource_type,
        resource_id: resource_id,
        actor_id: actor_id,
        actor_type: actor_type,
        action: event_type.to_s,
        actor: actor_id,
        target: resource_id,
        severity: level,
        metadata: meta,
        ip_address: ip_address,
        user_agent: user_agent,
        customer_id: customer_id,
        timestamp: Time.current
      }
      persist_event(ctx, customer_id, event_type, resource_type, resource_id, actor_id,
                    ip_address, user_agent, level, meta)
      Rails.logger.public_send(LOGGER_METHOD.fetch(level), "[AUDIT] #{entry.to_json}")
      true
    end

    def presence(value)
      value.respond_to?(:blank?) ? value.presence : value
    end

    def default_resource_id(ctx)
      model = ctx && ctx[:model]
      return model.id if model.respond_to?(:id)
      return model["id"] || model[:id] if model.is_a?(Hash)

      ctx && ctx[:model_id]
    end

    def default_resource_type(ctx)
      model = ctx && ctx[:model]
      return model.entity.name if model.is_a?(EntityEntry) && model.respond_to?(:entity) && model.entity
      return model.class.name.demodulize if model && !model.is_a?(Hash)

      nil
    end
    private_class_method :presence, :default_resource_id, :default_resource_type

    def persist_event(ctx, customer_id, event_type, resource_type, resource_id, actor_id,
                      ip_address, user_agent, severity, metadata)
      return if customer_id.blank?

      FlowchartAuditEvent.create!(
        customer_id: customer_id,
        flowchart_id: Integer(ctx && ctx[:flowchart_id], exception: false),
        event_type: event_type.to_s,
        resource_type: resource_type&.to_s.presence,
        resource_id: resource_id.nil? ? nil : resource_id.to_s,
        actor_user_id: Integer(actor_id, exception: false),
        ip: ip_address&.to_s.presence,
        user_agent: user_agent&.to_s.presence,
        severity: severity,
        metadata: metadata,
        created_at: Time.current
      )
    end
    private_class_method :persist_event
  end
end
