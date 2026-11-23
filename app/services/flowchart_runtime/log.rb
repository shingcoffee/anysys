# frozen_string_literal: true

module FlowchartRuntime
  # Logger sink for the log step (rails / stdout / file). Audit trail writes
  # are a separate audit_log action after migration.
  module Log
    class Error < StandardError; end

    BACKTRACE_LEVELS = %w[error fatal].freeze
    SENSITIVE_KEY = /\A.*(password|passwd|secret|token|ssn|card|cvv|authorization|api[_-]?key).*\z/i

    module_function

    def write(ctx, level:, logger:, message:, tags: {}, structured: false,
              include_backtrace: false, max_length: 0, file_path: nil)
      safe_tags = redact_tags(tags)
      text = format_message(message, level: level, tags: safe_tags, structured: structured,
                            include_backtrace: include_backtrace, max_length: max_length)
      case logger.to_s
      when "stdout" then $stdout.puts(text)
      when "file" then write_file(ctx, file_path, text)
      else write_rails(level, text, safe_tags)
      end
      true
    end

    def format_message(message, level:, tags:, structured:, include_backtrace:, max_length:)
      text = if structured
        payload = { level: level.to_s, message: message, timestamp: Time.current }
        payload[:tags] = tags if tags.is_a?(Hash) && tags.any?
        payload.to_json
      else
        message.to_s
      end
      if include_backtrace && BACKTRACE_LEVELS.include?(level.to_s)
        text = "#{text}\n#{caller.first(20).join("\n")}"
      end
      max_length.to_i.positive? ? text.truncate(max_length.to_i) : text
    end

    def redact_tags(tags)
      return {} unless tags.is_a?(Hash)

      tags.each_with_object({}) do |(key, val), acc|
        acc[key] = SENSITIVE_KEY.match?(key.to_s) ? "[FILTERED]" : val
      end
    end

    def write_file(ctx, file_path, text)
      tenant = ctx && ctx[:customer_id]
      raise Error, "tenant is required" if tenant.to_s.strip.empty?

      LogFile.append(tenant, file_path, text)
    rescue LogFile::Error => error
      raise Error, error.message
    end

    def write_rails(level, text, _tags)
      method_name = %w[debug info warn error fatal].include?(level.to_s) ? level.to_s : "info"
      Rails.logger.public_send(method_name, text)
    end
  end
end
