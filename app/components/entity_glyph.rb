# frozen_string_literal: true

# The tile that identifies an entity on the domains overview and in the
# Domains sidebar, so both read the same: a palette colour, a known icon, or
# the label's initials.
module EntityGlyph
  COLORS = EntityAttributeGroupingHelper::COLOR_CLASS_MAP
  # Entities rarely carry a palette colour, so one is derived from the name to
  # keep each entity recognisable across visits.
  DERIVED_COLORS = (COLORS.keys - ["slate"]).freeze

  module_function

  def color(entity)
    color = entity.color.to_s
    COLORS.key?(color) ? color : DERIVED_COLORS[Zlib.crc32(entity.name.to_s) % DERIVED_COLORS.size]
  end

  def text_class(color) = COLORS.fetch(color.to_s, COLORS["slate"])[:text]

  def icon(entity)
    key = entity.icon.to_s
    key if EntityAttributeGroupingHelper::ICON_PATHS.key?(key)
  end

  def icon_path(entity)
    EntityAttributeGroupingHelper::ICON_PATHS[icon(entity)]
  end

  def monogram(label)
    words = label.to_s.scan(/[[:alnum:]]+/)
    letters = words.size > 1 ? words.first(2).map { |word| word[0] } : [words.first.to_s[0]]
    letters.join.upcase
  end
end
