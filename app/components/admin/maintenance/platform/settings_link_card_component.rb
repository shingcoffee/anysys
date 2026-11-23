# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      # A "card" with a titled list of navigational links to a module's
      # platform-owner sub-settings pages (e.g. SMS credentials/templates,
      # Email credentials, Captcha settings). Consolidates the
      # icon + title + description + chevron row markup that used to be
      # duplicated per module in module_settings/show.html.erb.
      class SettingsLinkCardComponent < ApplicationComponent
        Link = Struct.new(:path, :title, :description, :icon, keyword_init: true)

        # Shared 24x24 outline icon paths (Heroicons-style), keyed by a short
        # symbol so callers don't repeat raw SVG path data.
        ICON_PATHS = {
          envelope:       "M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z",
          document:       "M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6z",
          bolt:           "M13 10V3L4 14h7v7l9-11h-7z",
          shield_check:   "M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z",
          lock_closed:    "M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z",
          clipboard_list: "M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4",
          microphone:     "M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z"
        }.freeze
        DEFAULT_ICON = :document
        LAYOUTS = %i[grid list].freeze

        def initialize(title:, subtitle:, links:, layout: :grid, show_heading: true)
          @title = title
          @subtitle = subtitle
          @links = links.map { |l| Link.new(**l) }
          @layout = LAYOUTS.include?(layout.to_sym) ? layout.to_sym : :grid
          @show_heading = show_heading
        end

        attr_reader :title, :subtitle, :links, :layout

        def show_heading?
          @show_heading
        end

        def icon_path(icon_key)
          ICON_PATHS.fetch(icon_key, ICON_PATHS[DEFAULT_ICON])
        end
      end
    end
  end
end
