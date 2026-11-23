# frozen_string_literal: true

module Websites
  module Sections
    # Plan tiers with one optional featured column (Stripe / Notion pricing).
    class PricingComponent < Websites::SectionComponent
      def tiers
        list("tiers").select { |tier| present_text?(tier["name"]) || present_text?(tier["price"]) }
      end

      def grid_class
        case tiers.size
        when 1 then "mx-auto max-w-md"
        when 2 then "mx-auto max-w-4xl md:grid-cols-2"
        when 4 then "md:grid-cols-2 lg:grid-cols-4"
        else "md:grid-cols-3"
        end
      end

      def featured?(tier)
        tier["highlight"].to_s == "featured"
      end

      def features(tier)
        tier["features"].to_s.split(/\r?\n/).map(&:strip).reject(&:blank?)
      end

      def tier_class(tier)
        # Subgrid keeps name / price / blurb / features / button on the same
        # baselines across tiers even when the blurbs wrap to different depths.
        base = "relative flex flex-col gap-6 rounded-3xl p-7 md:row-span-5 md:grid md:grid-rows-subgrid md:gap-6 md:p-8"
        return "#{base} #{card_border_class}" unless featured?(tier)

        surface = theme.dark? ? "bg-white/[0.06]" : "bg-white shadow-xl shadow-neutral-900/[0.06]"
        "#{base} #{surface} #{theme.accent_ring_class}"
      end

      def tier_button_class(tier)
        featured?(tier) ? primary_button_class : secondary_button_class
      end

      def featured_label
        prop("featured_label").presence || I18n.t("website.public.pricing.featured")
      end
    end
  end
end
