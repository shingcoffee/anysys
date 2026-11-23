# frozen_string_literal: true

module Websites
  module Admin
    # Appearance + accent swatch dots for catalog cards.
    class CatalogThemeDotsComponent < ApplicationComponent
      ACCENT_DOT = {
        "azure" => "bg-sky-500",
        "ink" => "bg-neutral-800",
        "gold" => "bg-amber-500",
        "forest" => "bg-emerald-600",
        "rose" => "bg-rose-500",
        "violet" => "bg-violet-500",
        "copper" => "bg-orange-700",
        "indigo" => "bg-indigo-600",
        "teal" => "bg-teal-600",
        "crimson" => "bg-red-700",
        "plum" => "bg-fuchsia-700",
        "olive" => "bg-lime-700"
      }.freeze

      def initialize(theme:)
        @theme = theme
      end

      attr_reader :theme

      def appearance_class
        if theme.dark?
          "bg-neutral-900 ring-1 ring-neutral-700"
        else
          "bg-white ring-1 ring-border"
        end
      end

      def accent_class
        ACCENT_DOT.fetch(theme.accent, "bg-sky-500")
      end

      def appearance_label
        I18n.t("website.admin.settings.theme.#{theme.appearance}")
      end

      def accent_label
        I18n.t("website.admin.settings.theme.#{theme.accent}")
      end
    end
  end
end
