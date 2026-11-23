# frozen_string_literal: true

class BadgeComponent < ApplicationComponent
  VARIANTS = {
    default: "badge-default",
    primary: "badge-accent",
    success: "badge-success",
    warning: "badge-warning",
    danger: "badge-danger",
    info: "bg-info-subtle text-info",
    purple: "bg-purple-100 text-purple-700"
  }.freeze

  SIZES = {
    sm: "px-2 py-0.5 text-xs",
    md: "px-2.5 py-1 text-sm"
  }.freeze

  attr_reader :variant, :size

  def initialize(variant: :default, size: :md, **html_attributes)
    @variant = variant.to_sym
    @size = size.to_sym
    @html_attributes = html_attributes
  end

  def variant_classes
    VARIANTS.fetch(variant, VARIANTS[:default])
  end

  def size_classes
    SIZES.fetch(size, SIZES[:md])
  end

  def component_classes
    ["badge", variant_classes, size_classes].join(" ")
  end

  def html_attributes
    base = { class: component_classes }
    merge_html_attributes(base, @html_attributes)
  end
end
