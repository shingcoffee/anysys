# frozen_string_literal: true

module Operations
  # RFC 6901 JSON Pointer helpers.
  module Pointer
    module_function

    def escape(token)
      token.to_s.gsub("~", "~0").gsub("/", "~1")
    end

    def join(*parts)
      parts.flatten.compact.map(&:to_s).reduce("") do |pointer, part|
        if part.start_with?("/") || (part.empty? && pointer.empty?)
          pointer.empty? ? part : "#{pointer}#{part}"
        else
          "#{pointer}/#{escape(part)}"
        end
      end
    end
  end
end
