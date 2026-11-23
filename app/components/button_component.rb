# frozen_string_literal: true

class ButtonComponent < ApplicationComponent
  BASE_CLASSES = "btn"

  VARIANTS = {
    primary: "btn-primary",
    secondary: "btn-secondary",
    danger: "btn-danger",
    success: "btn-success",
    ghost: "btn-ghost"
  }.freeze

  SIZES = {
    sm: "px-3 py-1.5 text-[13px]",
    md: "px-4 py-2 text-sm",
    lg: "px-5 py-2.5 text-sm"
  }.freeze

  attr_reader :variant, :size, :tag, :href, :disabled, :full_width

  def initialize(variant: :primary, size: :md, tag: :button, href: nil, disabled: false, full_width: false, **html_attributes)
    @variant = variant.to_sym
    @size = size.to_sym
    @tag = tag.to_sym
    @href = href
    @disabled = disabled
    @full_width = full_width
    @html_attributes = html_attributes
  end

  def variant_classes
    VARIANTS.fetch(variant, VARIANTS[:primary])
  end

  def size_classes
    SIZES.fetch(size, SIZES[:md])
  end

  def component_classes
    classes = [BASE_CLASSES, variant_classes, size_classes]
    classes << "w-full" if full_width
    classes << "opacity-50 cursor-not-allowed" if disabled
    classes.join(" ")
  end

  def html_attributes
    base = {
      class: component_classes
    }

    if tag == :button
      base[:type] = @html_attributes.fetch(:type, "button")
      base[:disabled] = true if disabled
    elsif tag == :a
      base[:href] = href
    end

    merge_html_attributes(base, @html_attributes)
  end
end
