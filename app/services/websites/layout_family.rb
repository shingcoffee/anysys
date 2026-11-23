# frozen_string_literal: true

module Websites
  # Maps a layout key to the skeleton family it was authored for: the longest
  # skeleton key that equals or prefixes it, or STANDALONE for layouts that
  # belong to no starter (article, gallery, pricing, ...).
  module LayoutFamily
    STANDALONE = "standalone"
    ALIASES = { "saas" => "saas_landing" }.freeze

    module_function

    def of(layout_key)
      key = layout_key.to_s
      match = skeleton_keys.find { |skeleton| key == skeleton || key.start_with?("#{skeleton}_") }
      return match if match

      prefix = key.split("_").first
      ALIASES.fetch(prefix) { skeleton_keys.include?(prefix) ? prefix : STANDALONE }
    end

    def standalone?(family)
      family.to_s == STANDALONE
    end

    def label(family)
      return I18n.t("website.admin.pages.new.filters.general") if standalone?(family)

      I18n.t("website.skeletons.#{family}.name")
    end

    # [[family, layouts], ...] in starter order with standalone layouts last;
    # `first` (usually the site's own starter) is pulled to the front.
    def group(layouts, first: nil)
      grouped = Array(layouts).group_by { |layout| of(layout.key) }
      order = Websites::Skeletons.keys + [STANDALONE]
      order = [first.to_s, *(order - [first.to_s])] if first.present? && order.include?(first.to_s)
      order.filter_map { |family| [family, grouped[family]] if grouped[family] }
    end

    def skeleton_keys
      Websites::Skeletons.keys.sort_by { |skeleton| -skeleton.length }
    end
  end
end
