# frozen_string_literal: true

module Member
  class StatusCardComponent < ApplicationComponent
    include UsesSiteChrome
    def initialize(label:, value:, icon:, cta_label:, cta_path:, tone: :default)
      @label     = label
      @value     = value
      @icon      = icon
      @cta_label = cta_label
      @cta_path  = cta_path
      @tone      = tone
    end

    attr_reader :label, :value, :icon, :cta_label, :cta_path, :tone

    def value_class
      "text-site-3xl font-semibold tracking-tight tabular-nums #{chrome.value_tone_class(tone)}"
    end
  end
end
