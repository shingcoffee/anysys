# frozen_string_literal: true

module Websites
  module Sections
    # A programme or timetable (TED, WWDC, an Equinox class schedule): the
    # time on the left, the session with its speaker and a line of copy in
    # the middle, and a track chip on the right.
    class AgendaComponent < Websites::SectionComponent
      def sessions
        list("sessions").select { |session| present_text?(session["title"]) }
      end

      def time_class
        "text-site-sm font-semibold uppercase tracking-[0.12em] tabular-nums #{theme.kicker_class}"
      end

      def session_title_class
        "text-balance break-words text-site-xl leading-snug md:text-site-2xl #{headline_font_class}"
      end
    end
  end
end
