# frozen_string_literal: true

module Websites
  module Sections
    # Static request-to-draft illustration. Content is supplied by the site,
    # while decorative line icons give each output card its own visual anchor.
    class AiPreviewComponent < Websites::SectionComponent
      OUTPUT_ICON_PATHS = [
        "M4 4h16v16H4z M4 9h16 M9 9v11 M12 13h5 M12 16h5",
        "M6 3h9l4 4v14H6z M14 3v5h5 M9 12h7 M9 16h4",
        "M3 4h18v16H3z M3 9h18 M7 6.5h.01 M10 6.5h.01 M7 13h4v4H7z M14 13h3 M14 17h3"
      ].freeze

      def items
        list("items")
      end

      def output_icon_path(index)
        OUTPUT_ICON_PATHS[index % OUTPUT_ICON_PATHS.length]
      end

      def frame_class
        theme.dark? ? "bg-neutral-900 ring-white/10 shadow-black/20" : "bg-neutral-50 ring-neutral-900/10 shadow-neutral-900/[0.08]"
      end

      def prompt_class
        theme.dark? ? "from-violet-950 to-neutral-900 text-violet-100 ring-violet-300/20" : "from-violet-50 to-violet-100/70 text-violet-950 ring-violet-900/10"
      end

      def prompt_muted_class
        theme.dark? ? "text-violet-200" : "text-violet-800"
      end

      def output_class
        theme.dark? ? "bg-neutral-950 ring-white/10" : "bg-white ring-neutral-900/10"
      end

      def icon_class
        theme.dark? ? "bg-neutral-800 text-neutral-300 ring-white/10" : "bg-neutral-50 text-neutral-600 ring-neutral-900/10"
      end
    end
  end
end
