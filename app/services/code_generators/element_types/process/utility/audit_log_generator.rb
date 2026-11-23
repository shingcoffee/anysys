# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Utility
        class AuditLogGenerator < BaseGenerator
          SEVERITIES = FlowchartRuntime::Audit::SEVERITIES
          OUTCOMES = FlowchartRuntime::Audit::OUTCOMES

          generator_metadata do
            description "Writes one structured audit line and a tenant-scoped flowchart_audit_events " \
                        "row for this submit (rolled back with the submit). Use this after an approval, " \
                        "payment, or record change; use log for operator-only debug text. eventType is " \
                        "required (order.approved). Blank actor, resource, IP, and user-agent fall back " \
                        "to ctx current_user_id, model, request_ip, and user_agent. metadata is extra " \
                        "ctx pairs; changesVariable copies a diff hash. severity (info default) picks " \
                        "the logger method; outcome success|failure is stored on metadata. Always " \
                        "succeeds unless persistence raises."
            category :utility
            version "1.4.0"
            presentation icon: "M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z",
                         color: "indigo", single_use: false, privileged: false
          end

          config_schema do
            literal :eventType, required: true, example: "record_updated", placeholder: true,
                    description: "Stable event name written on the row and log line, such as " \
                                 "record_updated or order.approved. Required. Prefer dotted past-tense names."
            literal :resourceType, placeholder: true,
                    description: "Type label for the resource, such as Order. Leave blank to use the " \
                                 "bound model entity name when ctx[:model] is set."
            input :resourceId, placeholder: true,
                  description: "Ctx path of the resource id, such as order.id. Leave blank to use " \
                               "ctx[:model].id when a record is loaded."
            input :actorId, default: "current_user_id", placeholder: true,
                  description: "Ctx path of the actor id. Default current_user_id. Leave blank to use " \
                               "that same seeded key at runtime."
            literal :actorType, placeholder: true,
                    description: "Actor kind, such as User or System. Leave blank to store User when " \
                                 "an actor id is present."
            mapping :metadata, key: :literal, value: :input, default: [],
                    description: "Extra key/value pairs on the event. Each value is a ctx path " \
                                 "(sku or order.number). outcome and changes are added separately."
            input :ipAddress, default: "request_ip", placeholder: true,
                  description: "Ctx path of the client IP. Default request_ip. Leave blank to use that seeded key."
            input :userAgent, default: "user_agent", placeholder: true,
                  description: "Ctx path of the client user agent. Default user_agent. Leave blank to use that seeded key."
            enum :severity, SEVERITIES, default: "info",
                 description: "Log severity stored on the row: debug, info (default), warn, error, or " \
                              "critical (logged as error). Pick warn or error for refused submits."
            enum :outcome, OUTCOMES, default: "success",
                 description: "Recorded on metadata.outcome. success (default) for a completed action; " \
                              "failure when this step audits a refused path."
            input :changesVariable, placeholder: true, group: :advanced,
                  description: "Ctx path of a diff hash stored under metadata.changes, such as " \
                               "record_diff from compare_data. Leave blank to omit."
          end

          def generate_body
            "FlowchartRuntime::Audit.write(ctx, #{write_args})"
          end

          private

          def write_args
            [
              "event_type: #{read(:eventType)}",
              ("resource_type: #{read(:resourceType)}" if value(:resourceType).to_s.strip.present?),
              ("resource_id: #{read(:resourceId)}" if value(:resourceId).to_s.strip.present?),
              ("actor_id: #{read(:actorId)}" if value(:actorId).to_s.strip.present?),
              ("actor_type: #{read(:actorType)}" if value(:actorType).to_s.strip.present?),
              ("metadata: #{metadata_hash}" unless metadata_hash == "{}"),
              ("ip_address: #{read(:ipAddress)}" if value(:ipAddress).to_s.strip.present?),
              ("user_agent: #{read(:userAgent)}" if value(:userAgent).to_s.strip.present?),
              ("severity: #{read(:severity)}" unless value(:severity).to_s == "info"),
              ("outcome: #{read(:outcome)}" unless value(:outcome).to_s == "success"),
              ("changes: #{read(:changesVariable)}" if value(:changesVariable).to_s.strip.present?)
            ].compact.join(", ")
          end

          def metadata_hash
            pairs = mapping_rows(:metadata).filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              val = row["value"] || row[:value]
              next if key.to_s.empty? || val.to_s.strip.empty?

              "#{key.to_s.inspect} => #{input_path(val)}"
            end
            "{#{pairs.join(', ')}}"
          end

          def mapping_rows(name)
            raw = value(name)
            case raw
            when Hash then raw.map { |key, val| { "key" => key.to_s, "value" => val } }
            when Array then raw
            else []
            end
          end

          def input_path(path)
            root, *rest = path.to_s.split(".", -1)
            return "nil" if root.to_s.empty?
            return "ctx[:#{root}]" if rest.empty? && safe_ident?(root)

            keys = rest.map { |segment| segment.match?(/\A\d+\z/) ? segment : ":#{segment}" }.join(", ")
            "FlowchartRuntime::Step.dig(ctx[:#{root}], #{keys})"
          end
        end
      end
    end
  end
end
