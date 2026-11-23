# frozen_string_literal: true

module Websites
  module Sections
    # A newspaper front (The New York Times, The Guardian): a ruled section
    # head, the lead story large with its photograph, two secondary stories
    # beside it, then a row of headline-only briefs.
    class StoryIndexComponent < Websites::SectionComponent
      SECONDARY = 2

      def stories
        @stories ||= list("stories").select { |story| present_text?(story["title"]) }
      end

      def lead
        stories.first
      end

      def secondary
        stories.drop(1).first(SECONDARY)
      end

      def briefs
        stories.drop(1 + SECONDARY)
      end

      def masthead?
        present_text?(prop("heading")) || present_text?(prop("kicker"))
      end

      def rule_class
        theme.dark? ? "border-white" : "border-neutral-950"
      end

      def story_tag(story, css_class, &block)
        href = item_href(story)
        extra = styler.item_class("stories")
        css = styler.item_css("stories")
        content_tag(
          href.present? ? :a : :article,
          href: href.presence,
          class: ["group #{css_class}", extra].compact_blank.join(" "),
          style: css,
          data: { site_el: "stories" },
          &block
        )
      end

      def title_class(story, size)
        hover = item_href(story).present? ? "decoration-1 underline-offset-[0.18em] group-hover:underline" : ""
        "text-balance break-words #{size} #{headline_font_class} #{hover}"
      end

      def story_kicker_class
        "text-site-xs font-semibold uppercase tracking-[0.16em] #{theme.kicker_class}"
      end

      def byline_class
        "text-site-sm #{muted_class}"
      end
    end
  end
end
