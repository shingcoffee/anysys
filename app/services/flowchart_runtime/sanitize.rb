# frozen_string_literal: true

require "loofah"
require "erb"

module FlowchartRuntime
  # FlowchartRuntime::Sanitize
  #
  # Thin wrapper around Loofah and Rails::Html sanitizers for flowchart
  # sanitize-input step generators. Owns a single error type
  # (FlowchartRuntime::Sanitize::Error) so generated step code never
  # rescues raw Loofah or sanitizer exceptions.
  module Sanitize
    class Error < StandardError; end
    SCRUB_MODES = %i[escape nofollow noop prune strip whitewash].freeze
    SANITIZERS = %w[strip_tags escape_html rails].freeze
    OVERFLOW = %w[truncate fail].freeze

    module_function

    # @param string [String]
    # @param mode   [Symbol] Loofah scrub mode (default :prune)
    # @return [String]
    # @raise  [FlowchartRuntime::Sanitize::Error]
    def apply(value, sanitizer:, tags: [], attributes: [],
              remove_null_bytes: true, max_length: 0,
              on_overflow: "truncate", trim_whitespace: false)
      mode = sanitizer.to_s
      raise Error, "unsupported sanitizer" unless SANITIZERS.include?(mode)

      text = value.to_s
      text = text.delete("\u0000") if remove_null_bytes
      text = case mode
             when "escape_html" then ERB::Util.html_escape(text)
             when "rails"
               Rails::HTML::SafeListSanitizer.new.sanitize(
                 text, tags: Array(tags).map(&:to_s), attributes: Array(attributes).map(&:to_s)
               )
             else strip_tags(text)
             end
      text = apply_length_limit(text.to_s, max_length, on_overflow)
      text = text.strip if trim_whitespace
      text
    end

    def apply_length_limit(text, max_length, on_overflow)
      limit = Integer(max_length || 0)
      return text unless limit.positive?
      return text.truncate(limit) unless text.length > limit
      raise Error, "input exceeds max length" if on_overflow.to_s == "fail"

      text.truncate(limit)
    end
    private_class_method :apply_length_limit

    def html(string, mode: :prune)
      scrub_mode = mode.to_s.downcase.to_sym
      raise Error, "unsupported scrub mode" unless SCRUB_MODES.include?(scrub_mode)

      Loofah.fragment(string.to_s).scrub!(scrub_mode).to_s
    end

    # @param string [String]
    # @return [String]
    # @raise  [FlowchartRuntime::Sanitize::Error]
    def strip_tags(string)
      Rails::Html::FullSanitizer.new.sanitize(string.to_s)
    end
  end
end
