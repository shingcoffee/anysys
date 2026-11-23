# frozen_string_literal: true

class QuickActionCardComponent < ApplicationComponent
  DEFAULT_COMPACT_ICON_CLASSES = "border border-border-subtle bg-surface text-text-muted shadow-xs group-hover:border-accent-muted group-hover:bg-accent-subtle group-hover:text-accent"

  def initialize(label:, description:, path:, icon: nil, compact: false, icon_classes: nil)
    @label = label
    @description = description
    @path = path
    @icon = icon
    @compact = compact
    @icon_classes = icon_classes
  end
  attr_reader :label, :description, :path, :icon

  def compact?
    @compact
  end

  def compact_icon_classes
    @icon_classes.presence || DEFAULT_COMPACT_ICON_CLASSES
  end
end
