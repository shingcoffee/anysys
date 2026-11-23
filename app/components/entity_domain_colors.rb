# frozen_string_literal: true

# Tailwind classes for each EntityDomain::COLORS key. Literal strings so
# Tailwind's source scan picks them up.
module EntityDomainColors
  DOTS = {
    "slate"  => "bg-slate-400",
    "blue"   => "bg-blue-500",
    "green"  => "bg-green-500",
    "amber"  => "bg-amber-500",
    "rose"   => "bg-rose-500",
    "purple" => "bg-purple-500",
    "teal"   => "bg-teal-500"
  }.freeze

  TILES = {
    "slate"  => "bg-slate-100 text-slate-700 ring-slate-200",
    "blue"   => "bg-blue-50 text-blue-700 ring-blue-200",
    "green"  => "bg-green-50 text-green-700 ring-green-200",
    "amber"  => "bg-amber-50 text-amber-700 ring-amber-200",
    "rose"   => "bg-rose-50 text-rose-700 ring-rose-200",
    "purple" => "bg-purple-50 text-purple-700 ring-purple-200",
    "teal"   => "bg-teal-50 text-teal-700 ring-teal-200"
  }.freeze

  # TILES without the fill, for a tile set on a white chip.
  CHIPS = {
    "slate"  => "text-slate-700 ring-slate-200",
    "blue"   => "text-blue-700 ring-blue-200",
    "green"  => "text-green-700 ring-green-200",
    "amber"  => "text-amber-700 ring-amber-200",
    "rose"   => "text-rose-700 ring-rose-200",
    "purple" => "text-purple-700 ring-purple-200",
    "teal"   => "text-teal-700 ring-teal-200"
  }.freeze

  module_function

  def dot(color) = DOTS.fetch(color.to_s, DOTS["slate"])
  def tile(color) = TILES.fetch(color.to_s, TILES["slate"])
  def chip(color) = CHIPS.fetch(color.to_s, CHIPS["slate"])
end
