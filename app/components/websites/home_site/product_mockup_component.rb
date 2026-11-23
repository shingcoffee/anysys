# frozen_string_literal: true

module Websites
  module HomeSite
    # Decorative, fully localized workspace preview for the lead hero. The
    # whole frame is a single labelled image to assistive technology.
    class ProductMockupComponent < ApplicationComponent
      NAV_GLYPHS = [
        "M4 13h6V4H4zM14 20h6v-9h-6zM4 20h6v-3H4zM14 7h6V4h-6z",
        "M4 4h16v16H4zM4 9h16M9 9v11",
        "M7 3h10v3H7zM6 5H4v16h16V5h-2M8 11h8M8 15h5",
        "M3 4h18v16H3zM3 9h18M7 6.5h.01M10 6.5h.01",
        "M3 6h18v12H3zM3 10h18M7 15h3",
        "M3 5h18v14H3zM3 6l9 7 9-7"
      ].freeze
      STATUS_TONES = %w[bg-emerald-50\ text-emerald-700 bg-amber-50\ text-amber-700 bg-violet-50\ text-violet-700 bg-emerald-50\ text-emerald-700].freeze
      AVATAR_TONES = %w[from-violet-500\ to-indigo-500 from-fuchsia-500\ to-pink-500 from-sky-400\ to-blue-500 from-amber-400\ to-orange-500].freeze

      def copy(key) = I18n.t("website.home_site.mockup.#{key}")
      def nav_items = Array(copy("nav"))
      def stats = Array(copy("stats")).map(&:stringify_keys)
      def columns = Array(copy("columns"))
      def rows = Array(copy("rows")).map(&:stringify_keys)
      def initials(name) = name.to_s.split(/\s+/).map { |part| part[0] }.join.first(2)
      def status_tone(index) = STATUS_TONES[index % STATUS_TONES.size]
      def avatar_tone(index) = AVATAR_TONES[index % AVATAR_TONES.size]
      def nav_glyph(index) = NAV_GLYPHS[index % NAV_GLYPHS.size]
    end
  end
end
