# frozen_string_literal: true

module FlowchartRuntime
  # Failure and read helpers used by generated step actions.
  module Step
    class Error < StandardError; end

    module_function

    def fail(ctx, code, field: nil, **details)
      raise Error, "error code is required" if code.to_s.strip.empty?

      append(
        ctx,
        I18n.t("flowchart_runtime.errors.#{code}", **details),
        code,
        field,
        details
      )
      false
    end

    def fail_message(ctx, localized, code: :business_error, field: nil, variables: nil)
      text = LocalizedText.resolve(localized, locale: I18n.locale, variables: variables)
      append(ctx, text, code, field, {})
      false
    end

    def attempt(ctx, code, *error_classes)
      yield
    rescue *error_classes => error
      fail(ctx, code, reason: error.class.name.demodulize)
      Array(ctx[:error_details]).last["diagnostic"] = error.message
      false
    end

    def dig(value, *keys)
      keys.reduce(value) do |current, key|
        break nil if current.nil?

        if current.is_a?(Array)
          break nil unless key.is_a?(Integer)

          current[key]
        elsif current.is_a?(Hash)
          if current.key?(key)
            current[key]
          elsif key.is_a?(Symbol) && current.key?(key.to_s)
            current[key.to_s]
          elsif key.respond_to?(:to_sym) && current.key?(key.to_sym)
            current[key.to_sym]
          end
        elsif current.is_a?(EntityEntry)
          current.flowchart_value(key)
        end
      end
    end

    def append(ctx, message, code, field, details)
      ctx[:errors] ||= []
      text = message.to_s
      ctx[:errors] << text unless ctx[:errors].include?(text)
      ctx[:error_details] ||= []
      ctx[:error_details] << {
        "code" => code.to_s,
        "field" => field&.to_s,
        "message" => text,
        "details" => details.transform_values(&:to_s)
      }
    end
    private_class_method :append
  end
end
