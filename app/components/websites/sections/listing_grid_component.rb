# frozen_string_literal: true

module Websites
  module Sections
    # Photo-first listings with a badge, title, rating, a meta line and a
    # price (Airbnb stays, Sotheby's homes, a shop's bestsellers). `aspect`
    # frames every photo the same way: square, portrait (products) or
    # landscape (houses).
    class ListingGridComponent < Websites::SectionComponent
      ASPECT_CLASSES = {
        "square" => "aspect-square",
        "portrait" => "aspect-[4/5]",
        "landscape" => "aspect-[4/3]"
      }.freeze

      def listings
        list("listings").select { |listing| present_text?(listing["title"]) }
      end

      def aspect_class
        ASPECT_CLASSES.fetch(props["aspect"].to_s, ASPECT_CLASSES["square"])
      end

      def grid_class
        (listings.size % 4).zero? ? "sm:grid-cols-2 lg:grid-cols-4" : "sm:grid-cols-2 lg:grid-cols-3"
      end

      def rating_label(listing)
        I18n.t("website.public.listings.rating", rating: listing["rating"].to_s.strip)
      end

      def listing_tag(listing, &block)
        href = item_href(listing)
        html = { class: "group flex min-w-0 flex-col gap-4" }
        html[:href] = href if href.present?
        extra = styler.item_class("listings", framed: false)
        html[:class] = [html[:class], extra].compact_blank.join(" ") if extra
        css = styler.item_css("listings")
        html[:style] = css if css
        html[:data] = { site_el: "listings" }
        content_tag(href.present? ? :a : :article, **html, &block)
      end
    end
  end
end

