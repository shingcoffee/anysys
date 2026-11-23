# frozen_string_literal: true

module FormFields
  class ListElementComponent < BaseElementComponent
    STYLES = %w[bullet numbered none].freeze

    attr_reader :content_text, :list_style

    def initialize(content_text:, list_style: "bullet", theme: {})
      super(theme: theme)
      @content_text = content_text
      @list_style = STYLES.include?(list_style) ? list_style : "bullet"
    end

    def items
      content_text.to_s.split("\n").map(&:strip).reject(&:blank?)
    end

    def list_tag
      case list_style
      when "numbered" then "ol"
      else "ul"
      end
    end

    def list_classes
      case list_style
      when "bullet"   then "list-disc pl-5 space-y-1"
      when "numbered" then "list-decimal pl-5 space-y-1"
      when "none"     then "space-y-1"
      end
    end
  end
end
