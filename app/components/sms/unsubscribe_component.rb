# frozen_string_literal: true

module Sms
  class UnsubscribeComponent < ApplicationComponent
    def initialize(unsubscribe:, errors:)
      @unsubscribe, @errors = unsubscribe, errors || {}
    end

    def ui(key) = t("sms_campaign_ui.unsubscribe.#{key}")
  end
end
