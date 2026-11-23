# frozen_string_literal: true

module FlowchartRuntime
  module Json
    class Error < StandardError; end

    module_function

    def parse(text, max_bytes:)
      limit = Integer(max_bytes, exception: false)
      raise Error, "max_bytes must be non-negative" unless limit && !limit.negative?

      payload = text.to_s
      raise Error, "payload exceeds maximum bytes" if payload.bytesize > limit

      JSON.parse(payload)
    rescue JSON::ParserError => e
      raise Error, e.message
    end
  end
end
