# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class LogGenerator < BaseGenerator
          LOG_LEVELS = %w[debug info warn error fatal].freeze
          LOGGERS = %w[rails file].freeze
          SAFE_LOG_FILENAME = /\A[A-Za-z0-9._-]+\z/

          generator_metadata do
            description "Writes a message to the Rails logger or a tenant-scoped file under tmp/flowchart_logs. Use this for operator diagnostics, not for storing business data (use assign_value or create_model). Sensitive tag keys (password, token, secret, ssn, card) are redacted. Reads optional tag ctx paths; writes nothing into a result variable. Fails with log.failed when the file logger has no tenant or an unsafe filePath."
            category :data_operations
            version "3.0.0"
            presentation icon: "M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01",
                          color: "amber", single_use: false, privileged: false
          end

          config_schema do
            enum :logLevel, LOG_LEVELS, default: "info",
                 description: "Severity written with the message. debug/info/warn/error/fatal map to Rails.logger methods. Default info."
            template :messageTemplate, required: true, example: "Processing step", placeholder: true,
                     description: "Message to write. Plain text, or a Liquid template such as Order {{ order_number }} paid."
            enum :logger, LOGGERS, default: "rails",
                 description: "Where the message is written. rails uses Rails.logger; file appends under tmp/flowchart_logs/<customer_id>/."
            literal :filePath, placeholder: true, example: "custom.log", visible: { logger: "file" },
                    description: "Basename of the tenant log file (no directories). Example: payments.log. Required when logger is file."
            mapping :tags, key: :literal, value: :input, default: [], visible: { structured: true },
                    description: "Extra values attached to a structured JSON log. Keys matching password/token/secret/ssn/card are redacted. Example: order_id -> order.id."
            flag :includeBacktrace, default: false, group: :advanced,
                 description: "Append the call stack on error and fatal levels. Default false. Ignored for debug/info/warn."
            flag :structured, default: false, group: :advanced,
                 description: "Write a JSON payload with level, message, timestamp, and tags. Default false writes the message text."
            integer :maxMessageLength, min: 0, default: 0, group: :advanced,
                    description: "Truncate the message to this many characters. 0 means no truncation. Example: 500."
            requires :filePath, when: { logger: "file" }
            validate do |cfg, errors|
              next unless cfg["logger"] == "file" && cfg["filePath"].present?

              raw = cfg["filePath"].to_s.strip
              if raw.include?("..") || raw.include?("\0") || raw.start_with?("/")
                errors.add(:filePath, :unsafe_path)
              elsif !SAFE_LOG_FILENAME.match?(File.basename(raw))
                errors.add(:filePath, :unsafe_path)
              end
            end
          end

          def generate_body
            body(
              attempt('"log.failed"', FlowchartRuntime::Log::Error) do
                "FlowchartRuntime::Log.write(ctx, #{write_args})"
              end
            )
          end

          private

          def write_args
            tags = tags_literal
            structured = read(:structured)
            backtrace = read(:includeBacktrace)
            max_length = read(:maxMessageLength)
            file_path = optional_literal(:filePath)
            args = [
              "level: #{read(:logLevel)}",
              "logger: #{read(:logger)}",
              "message: #{read(:messageTemplate)}"
            ]
            args << "tags: #{tags}" unless tags == "{}"
            args << "structured: true" if structured == "true"
            args << "include_backtrace: true" if backtrace == "true"
            args << "max_length: #{max_length}" unless max_length == "0"
            args << "file_path: #{file_path}" unless file_path == "nil"
            args.join(", ")
          end

          def tags_literal
            rows = Array(value(:tags))
            return "{}" if rows.blank?

            pairs = rows.filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              val = row["value"] || row[:value]
              next if key.to_s.empty? || val.to_s.strip.empty?

              "#{key.to_s.inspect} => #{input_path(val)}"
            end
            "{#{pairs.join(', ')}}"
          end

          def input_path(path)
            root, *rest = path.to_s.split(".", -1)
            return "nil" if root.to_s.empty?
            return "ctx[:#{root}]" if rest.empty? && safe_ident?(root)

            keys = rest.map { |segment| segment.match?(/\A\d+\z/) ? segment : ":#{segment}" }.join(", ")
            "FlowchartRuntime::Step.dig(ctx[:#{root}], #{keys})"
          end

          def optional_literal(name)
            raw = value(name)
            raw.to_s.strip.empty? ? "nil" : read(name)
          end
        end
      end
    end
  end
end
