# frozen_string_literal: true

module Admin
  module Pages
    # Per-row kebab menu on the forms list: Manage access, Preview in a new
    # tab, then Launch / Take offline.
    class RowMenuComponent < ApplicationComponent
      ICONS = {
        manage:  "M15.75 6a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0zM4.5 20.118a7.5 7.5 0 0115 0A17.933 17.933 0 0112 21.75c-2.676 0-5.216-.584-7.5-1.632z",
        preview: "M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178zM15 12a3 3 0 11-6 0 3 3 0 016 0z",
        launch:  "M5.25 5.653c0-.856.917-1.398 1.667-.986l11.54 6.348a1.125 1.125 0 010 1.971l-11.54 6.347a1.125 1.125 0 01-1.667-.985V5.653z",
        offline: "M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636"
      }.freeze

      ITEM_CLASSES = "flex items-center gap-2.5 rounded-md px-2.5 py-1.5 text-sm font-medium transition-base hover:bg-surface-hover"

      attr_reader :page, :manage_path, :preview_path, :launch_path, :publishing_frame

      def initialize(page:, manage_path:, preview_path:, launch_path:, publishing_frame:)
        @page             = page
        @manage_path      = manage_path
        @preview_path     = preview_path
        @launch_path      = launch_path
        @publishing_frame = publishing_frame
      end

      def item_classes(tone = :default)
        tone == :danger ? "#{ITEM_CLASSES} text-danger" : "#{ITEM_CLASSES} text-text-primary"
      end

      def icon(key, tone = :default)
        color = tone == :danger ? "text-danger" : "text-text-muted"
        tag.svg(class: "size-4 shrink-0 #{color}", fill: "none", viewBox: "0 0 24 24",
                stroke: "currentColor", "stroke-width": 1.75, "aria-hidden": true) do
          tag.path(d: ICONS.fetch(key), "stroke-linecap": "round", "stroke-linejoin": "round")
        end
      end

      def menu_link(label, path, icon_key, tone: :default, **options)
        link_to(path, class: item_classes(tone), role: "menuitem", **options) do
          safe_join([icon(icon_key, tone), label])
        end
      end

      def new_tab_attributes
        { target: "_blank", rel: "noopener noreferrer", data: { turbo_frame: "_top" } }
      end
    end
  end
end
