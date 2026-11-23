# frozen_string_literal: true

module Websites
  module Sections
    # Horizontally scrolling picture cards — Spotify playlists / Airbnb categories.
    class CollectionRailComponent < Websites::SectionComponent
      ASPECT_CLASSES = {
        "square" => "aspect-square",
        "portrait" => "aspect-[4/5]",
        "landscape" => "aspect-[4/3]"
      }.freeze

      # The rail bleeds to the viewport edge but its first card (and every
      # snap point) lines up with the centred 80rem header column.
      RAIL_INSET_CLASS = [
        "px-5 scroll-px-5 sm:px-8 sm:scroll-px-8",
        "lg:px-[max(3rem,calc((100%-80rem)/2+3rem))] lg:scroll-px-[max(3rem,calc((100%-80rem)/2+3rem))]"
      ].join(" ").freeze

      def items
        list("items").select do |item|
          present_text?(item["title"]) || present_text?(item["meta"]) || present_text?(item["image_url"])
        end
      end

      def aspect_class
        ASPECT_CLASSES.fetch(props["aspect"].to_s, ASPECT_CLASSES["portrait"])
      end

      def card_width_class
        case props["aspect"].to_s
        when "landscape" then "w-[min(20rem,78vw)] sm:w-80"
        when "square" then "w-[min(16rem,70vw)] sm:w-64"
        else "w-[min(15rem,68vw)] sm:w-60"
        end
      end
    end
  end
end
