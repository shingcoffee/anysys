# frozen_string_literal: true

module Websites
  module Admin
    # One theme token choice on Settings / Website, drawn as a small visual of
    # the look (page tone, accent swatch, type specimen, spacing). The radio
    # stays a website-theme-picker token so the live preview keeps working.
    class ThemeOptionComponent < ApplicationComponent
      CARD_CLASS = [
        "flex h-full flex-col gap-2 rounded-lg border border-border-subtle bg-surface p-2 text-sm text-text-secondary",
        "transition-colors hover:border-border peer-checked:border-accent peer-checked:text-text-primary",
        "peer-checked:ring-1 peer-checked:ring-accent peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-accent"
      ].join(" ")

      SWATCH_CLASS = [
        "flex size-9 items-center justify-center rounded-full text-white shadow-xs ring-1 ring-black/10 ring-offset-2 ring-offset-surface transition",
        "peer-checked:ring-2 peer-checked:ring-text-primary peer-focus-visible:outline-2 peer-focus-visible:outline-offset-4 peer-focus-visible:outline-accent"
      ].join(" ")

      ACCENT_SWATCH = {
        "azure" => "bg-sky-500",
        "ink" => "bg-neutral-900",
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

      CORNER_SPECIMEN = { "sharp" => "rounded-[2px]", "soft" => "rounded-lg", "round" => "rounded-2xl" }.freeze
      NEUTRAL_SPECIMEN = {
        "neutral" => %w[bg-neutral-100 bg-neutral-300 bg-neutral-600],
        "warm" => %w[bg-stone-100 bg-stone-300 bg-stone-600],
        "cool" => %w[bg-slate-100 bg-slate-300 bg-slate-600]
      }.freeze

      def initialize(token:, value:, checked: false, described_by: nil)
        @token = token.to_s
        @value = value.to_s
        @checked = checked
        @described_by = described_by
      end

      attr_reader :token, :value

      def input_options
        {
          type: "radio",
          class: "peer sr-only",
          name: "website[theme][#{token}]",
          id: "website_theme_#{token}_#{value}",
          value: value,
          checked: @checked,
          aria: { describedby: @described_by },
          data: { website_theme_picker_target: "token", token: token }
        }
      end

      def label
        token == "neutral" ? t("website.admin.settings.theme.neutrals.#{value}") : t("website.admin.settings.theme.#{value}")
      end

      def accent?
        token == "accent"
      end

      def dark?
        value == "dark"
      end

      def swatch_class
        "#{SWATCH_CLASS} #{ACCENT_SWATCH.fetch(value, 'bg-accent')}"
      end

      def specimen_class
        [Websites::Theme.new("type" => value).type_headline_class, "text-2xl leading-none text-text-primary"].join(" ")
      end

      # Scopes the pairing's heading family onto the specimen only.
      def specimen_style
        "--font-site-heading: #{Websites::Theme.new('type' => value).heading_stack};"
      end

      def corner_class
        CORNER_SPECIMEN.fetch(value, "rounded-lg")
      end

      def neutral_swatches
        NEUTRAL_SPECIMEN.fetch(value, NEUTRAL_SPECIMEN.fetch("neutral"))
      end

      def density_bars
        value == "compact" ? 4 : 2
      end

      def density_class
        value == "compact" ? "gap-1 p-1.5" : "gap-2.5 p-3"
      end
    end
  end
end
