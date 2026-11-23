# frozen_string_literal: true

class MenuBarComponent < ApplicationComponent
  UTILITY_KEYS = %i[settings maintenance].freeze

  TAB_BASE = "group/tab relative flex h-12 shrink-0 cursor-pointer list-none items-center px-0.5 no-underline " \
             "focus-visible:outline-none [&::-webkit-details-marker]:hidden"
  TAB_INDICATOR = "after:absolute after:inset-x-2 after:bottom-0 after:h-0.5 after:rounded-full after:bg-accent"
  LABEL_BASE = "flex items-center gap-2 whitespace-nowrap rounded-md px-2 py-1.5 text-sm xl:px-2.5 font-medium transition-colors " \
               "group-hover/tab:bg-surface-hover group-focus-visible/tab:ring-2 group-focus-visible/tab:ring-accent"
  LABEL_ACTIVE = "text-text-primary [&>svg:first-child]:text-accent"
  LABEL_IDLE = "text-text-secondary group-hover/tab:text-text-primary group-open:bg-surface-hover group-open:text-text-primary"

  CHILD_BASE = "group/child flex items-start gap-3 rounded-lg p-2.5 no-underline transition-colors " \
               "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
  CHILD_ICON_BASE = "flex size-9 shrink-0 items-center justify-center rounded-lg border transition-colors"

  def initialize(customer:, items:, current_menu_item:, current_path: nil)
    @customer = customer
    @items = items || []
    @current_menu_item = current_menu_item
    @current_path = current_path.to_s
  end

  attr_reader :customer, :items, :current_menu_item, :current_path

  def render?
    items.any?
  end

  def path_for(item) = item.path_for(customer)

  def primary_items
    items.reject { |item| UTILITY_KEYS.include?(item.key) }
  end

  def utility_items
    items.select { |item| UTILITY_KEYS.include?(item.key) }
  end

  def active_item?(item)
    item.key == active_key
  end

  def tab_classes(item)
    active_item?(item) ? "#{TAB_BASE} #{TAB_INDICATOR}" : TAB_BASE
  end

  def label_classes(item)
    "#{LABEL_BASE} #{active_item?(item) ? LABEL_ACTIVE : LABEL_IDLE}"
  end

  def child_classes(active)
    "#{CHILD_BASE} #{active ? 'bg-accent-subtle' : 'hover:bg-surface-hover'}"
  end

  def child_icon_classes(active)
    state = active ? "border-accent-muted bg-surface text-accent" : "border-border-subtle bg-canvas-elevated text-text-secondary group-hover/child:text-text-primary"
    "#{CHILD_ICON_BASE} #{state}"
  end

  def child_label_classes(active)
    "block text-sm font-medium #{active ? 'text-accent-text' : 'text-text-primary'}"
  end

  private

  def active_key
    @active_key ||= items.find { |item| item.active_for?(customer, current_path) }&.key || current_menu_item
  end
end
