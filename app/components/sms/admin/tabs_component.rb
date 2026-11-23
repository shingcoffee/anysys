# frozen_string_literal: true

module Sms
  module Admin
    class TabsComponent < BaseComponent
      attr_reader :tabs

      def initialize(tabs:)
        @tabs = tabs
      end

      def render?
        tabs.any?
      end

      def nav_label
        t("sms_campaign_ui.shared.navigation")
      end
    end
  end
end
