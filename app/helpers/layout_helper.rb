# frozen_string_literal: true

module LayoutHelper
  WIDTH_CLASSES = {
    narrow: "max-w-3xl mx-auto px-3 sm:px-4 lg:px-8",
    wide:   "max-w-7xl mx-auto px-3 sm:px-4 lg:px-8",
    full:   "w-full px-3 sm:px-4 lg:px-8",
    edge:   "w-full"
  }.freeze

  ADMIN_PATH = %r{\A/\d+/admin(?:/|\z)}.freeze
  SETTINGS_PATH = %r{\A/\d+/admin/settings(?:/|\z)}.freeze

  def container_width_class(tier)
    key = tier.to_s.to_sym if tier
    WIDTH_CLASSES.fetch(key, WIDTH_CLASSES[:wide])
  end

  def default_container_width_for(path)
    return :full if path.to_s.match?(SETTINGS_PATH)

    path.to_s.match?(ADMIN_PATH) ? :full : :wide
  end
end
