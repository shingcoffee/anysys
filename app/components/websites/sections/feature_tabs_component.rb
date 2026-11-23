# frozen_string_literal: true

module Websites
  module Sections
    # Tabbed product tour pairing copy with a framed still (Linear / Notion).
    class FeatureTabsComponent < Websites::SectionComponent
      def tabs
        list("tabs").select { |tab| present_text?(tab["label"]) || present_text?(tab["title"]) }
      end

      def tab_label(tab)
        present_text?(tab["label"]) ? tab["label"].to_s : tab["title"].to_s
      end

      def uid
        @uid ||= "feature-tabs-#{object_id}"
      end

      def tab_dom_id(index)
        "#{uid}-tab-#{index}"
      end

      def panel_dom_id(index)
        "#{uid}-panel-#{index}"
      end

      def tablist_label
        I18n.t("website.public.feature_tabs.tablist")
      end

      def tab_base_class
        "relative -mb-px shrink-0 border-b-2 px-4 py-3 text-site-base font-medium transition-colors duration-200"
      end

      def tab_active_class
        "border-current #{theme.kicker_class}"
      end

      def tab_inactive_class
        "border-transparent #{muted_class}"
      end

      def tab_class(active)
        "#{tab_base_class} #{active ? tab_active_class : tab_inactive_class}"
      end
    end
  end
end
