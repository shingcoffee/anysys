# frozen_string_literal: true

# Tailwind classes for a SidebarNode `tone`. "domain.<color>" and
# "entity.<color>" tint the tile with an EntityDomain or entity palette
# colour; any other tone is a feature-module key and returns nil so the
# caller falls back to the module colours.
module SidebarTone
  module_function

  def domain(color) = "domain.#{color}"
  def entity(color) = "entity.#{color}"

  # An active tile lifts onto a white chip so it reads against the row's
  # accent highlight.
  def classes(tone, active: false)
    family, color = tone.to_s.split(".", 2)
    case family
    when "domain"
      tint = active ? "bg-surface shadow-xs #{EntityDomainColors.chip(color)}" : EntityDomainColors.tile(color)
      "ring-1 ring-inset #{tint}"
    when "entity"
      surface = active ? "bg-surface shadow-xs ring-1 ring-inset ring-accent/20" : "bg-surface-active"
      "#{surface} #{EntityGlyph.text_class(color)}"
    end
  end
end
