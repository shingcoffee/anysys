# frozen_string_literal: true

module Member
  class EmptyStateComponent < ApplicationComponent
    include UsesSiteChrome
    def initialize(headline:, body:, icon: :plus, cta_label: nil, cta_path: nil)
      @headline  = headline
      @body      = body
      @icon      = icon
      @cta_label = cta_label
      @cta_path  = cta_path
    end

    attr_reader :headline, :body, :icon, :cta_label, :cta_path

    def cta?
      cta_label.present? && cta_path.present?
    end

    def icon_path
      case icon
      when :document
        "M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
      when :search
        "M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
      when :inbox
        "M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"
      else
        # :plus (default) and any unknown icon
        "M12 4v16m8-8H4"
      end
    end
  end
end
