# frozen_string_literal: true

class CardComponent < ApplicationComponent
  VARIANTS = {
    default: "card",
    bordered: "card",
    elevated: "card-elevated",
    flat: "bg-canvas-elevated border border-border-subtle rounded-lg"
  }.freeze

  PADDINGS = {
    none: "",
    sm: "p-4",
    md: "p-6",
    lg: "p-8"
  }.freeze

  attr_reader :variant, :padding

  def initialize(variant: :default, padding: :md, **html_attributes)
    @variant = variant.to_sym
    @padding = padding.to_sym
    @html_attributes = html_attributes
  end

  def variant_classes
    VARIANTS.fetch(variant, VARIANTS[:default])
  end

  def padding_classes
    PADDINGS.fetch(padding, PADDINGS[:md])
  end

  def component_classes
    [variant_classes, padding_classes].compact_blank.join(" ")
  end

  def html_attributes
    base = { class: component_classes }
    merge_html_attributes(base, @html_attributes)
  end
end
