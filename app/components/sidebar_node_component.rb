# frozen_string_literal: true

class SidebarNodeComponent < ApplicationComponent
  include Admin::Maintenance::Platform::ModuleSettingsHelper

  SOFT_ROW_CLASSES = "group relative flex min-w-0 items-center gap-2.5 rounded-md py-1 text-body-sm transition-base focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent".freeze
  # Short accent bar drawn over the sub-menu guide line beside the selected child.
  SOFT_CHILD_MARKER = "before:absolute before:-left-[9px] before:inset-y-1.5 before:w-0.5 before:rounded-full before:bg-accent".freeze
  SOFT_MENU_ITEMS = %i[settings modules pages entities].freeze
  # Pages and Entities list customer-named records, which can be long
  # machine-generated names; they truncate (full name on hover) instead of wrapping.
  TRUNCATED_MENU_ITEMS = %i[pages entities].freeze

  attr_reader :node, :current_path, :depth, :mobile, :filterable

  def initialize(node:, current_path:, depth: 0, mobile: false, filterable: false, selected_key: :default)
    @node = node
    @current_path = current_path
    @depth = depth
    @mobile = mobile
    @filterable = filterable
    @selected_key = selected_key
  end

  def mobile?
    @mobile
  end

  def filterable?
    @filterable
  end

  def settings?
    node.menu_item == :settings
  end

  # Modules, Pages, and Entities borrow the settings chrome (soft active pill)
  # so every record-browsing sidebar reads the same way.
  def soft?
    SOFT_MENU_ITEMS.include?(node.menu_item)
  end

  def truncate_label?
    TRUNCATED_MENU_ITEMS.include?(node.menu_item)
  end

  def label_classes
    return "truncate flex-1" unless soft?

    truncate_label? ? "min-w-0 flex-1 truncate" : "min-w-0 flex-1 break-words"
  end

  def label_title
    node.label if truncate_label?
  end

  # Numeric badges (e.g. page counts) read as a quiet trailing count rather
  # than a pill, so a long list of counts does not compete with the labels.
  def count_badge?
    soft? && node.badge.present? && node.badge[:label].to_s.match?(/\A\d+\z/)
  end

  def count_classes
    tone = if active? then "text-accent"
           elsif node.badge[:label].to_s == "0" then "text-text-muted/60"
           else "text-text-muted"
           end
    "ml-auto shrink-0 pl-2 text-[11px] font-medium tabular-nums #{tone}"
  end

  def active?
    return false if @selected_key.nil?
    return node.key == @selected_key unless @selected_key == :default

    path_active?(node)
  end

  # The longest matching prefix wins, so a general item such as All Pages does
  # not stay selected beside the more specific page the customer opened.
  def self.selected_key(nodes, current_path)
    best_key = nil
    best_score = -1
    walk = lambda do |list|
      Array(list).each do |candidate|
        score = match_score(candidate, current_path)
        if score && score > best_score
          best_score = score
          best_key = candidate.key
        end
        walk.call(candidate.children)
      end
    end
    walk.call(nodes)
    best_key
  end

  def self.match_score(node, current_path)
    path = current_path.to_s.split(/[?#]/, 2).first.to_s.delete_suffix("/")
    scores = []
    if node.path.present?
      candidate = node.path.to_s.delete_suffix("/")
      scores << candidate.length if candidate.present? && path == candidate
    end
    node.match_paths.each do |candidate|
      next if candidate.blank?

      normalized = candidate.to_s.delete_suffix("/")
      scores << normalized.length if path == normalized
    end
    Array(node.match_prefix).compact.each do |prefix|
      next if prefix.blank?

      normalized = prefix.to_s.delete_suffix("/")
      scores << normalized.length if path == normalized || path.start_with?("#{normalized}/")
    end
    scores.max
  end

  # Follows the same selection as `active?`, so the open group always holds the
  # highlighted item.
  def descendant_active?
    return node.children.any? { |child| child_active?(child) } if @selected_key == :default

    !@selected_key.nil? && descendant_selected?(node)
  end

  # A selected group (e.g. the Domains row whose page is open) shows its children.
  def open?
    active? || descendant_active?
  end

  def row_classes
    return soft_row_classes if soft?

    base = "group relative flex items-center gap-2.5 pr-3 py-2 text-[13px] rounded-lg transition-base"
    state = if active?
              "bg-accent-subtle text-accent font-medium before:absolute before:left-0 before:top-1 before:bottom-1 before:w-0.5 before:rounded-full before:bg-accent"
            else
              "text-text-secondary hover:bg-surface-hover hover:text-text-primary"
            end
    "#{base} #{state} #{indent_class}"
  end

  # Modules and Settings: compact desktop rows (touch-sized on mobile), a tinted
  # icon tile on top-level rows, and plain text rows inside a guide-lined sub-menu.
  def soft_row_classes
    height = if mobile? then "min-h-11"
             elsif depth.zero? then "min-h-9"
             else "min-h-8"
             end
    state = if active?
              "bg-accent-subtle font-medium text-accent"
            elsif descendant_active?
              "font-medium text-text-primary hover:bg-surface-hover"
            else
              "text-text-secondary hover:bg-surface-hover hover:text-text-primary"
            end
    marker = SOFT_CHILD_MARKER if active? && depth.positive?
    [SOFT_ROW_CLASSES, height, depth.zero? || icon_tile? ? "px-2" : "px-3", state, marker].compact.join(" ")
  end

  # Top-level rows always show their tile; nested rows only when tinted, so
  # plain sub-menus (Settings, Modules) stay text-only.
  def icon_tile?
    soft? && (node.icon.present? || node.monogram.present?) && (depth.zero? || node.tone.present?)
  end

  def icon_glyph?
    !soft? && node.icon.present?
  end

  def tile_size_classes
    depth.zero? ? "size-6" : "size-5"
  end

  def tile_classes
    return "bg-surface text-accent ring-1 ring-inset ring-accent/20" if node.tone.blank? && active?

    SidebarTone.classes(node.tone, active: active?) || module_color_classes(node.tone)
  end

  def sub_list_classes
    if soft?
      "relative ml-[19px] mt-0.5 flex flex-col gap-0.5 border-l border-border-subtle py-0.5 pl-2"
    else
      "relative mt-1 flex flex-col gap-0.5 before:absolute before:left-[19px] before:top-0 before:bottom-2 before:w-px before:bg-border-subtle"
    end
  end

  def indent_class
    return "" if soft?

    case depth
    when 0 then "pl-3"
    when 1 then "pl-8"
    when 2 then "pl-11"
    else "pl-14"
    end
  end

  def li_attributes
    return {} unless filterable?

    { data: { list_filter_target: "item", search_text: search_blob } }
  end

  def search_blob
    labels_for(node).join(" ")
  end

  private

  def labels_for(n)
    labels = settings? ? [SettingsContributor.search_text(n)] : [n.label, n.description].compact
    labels + n.children.flat_map { |child| labels_for(child) }
  end

  # Modules groups are collapsible <details>: hide a matching group summary
  # only when neither it nor any descendant matches.
  def details_target?
    filterable? && node.children.any?
  end

  def path_active?(n)
    return true if n.path.present? && current_path == n.path

    # Exact aliases are path-only (like request.path), tolerate a trailing slash,
    # and never select descendants. Nodes without aliases keep existing matching.
    if n.match_paths.any?
      path = current_path.to_s.split(/[?#]/, 2).first.to_s.delete_suffix("/")
      return true if n.match_paths.any? { |candidate| candidate.present? && path == candidate.delete_suffix("/") }
    end

    # match_prefix may be a single String or an Array<String> of sibling path
    # prefixes (e.g. in-page tabs sharing one sidebar entry).
    Array(n.match_prefix).compact.any? do |prefix|
      next false if prefix.blank?
      current_path == prefix || current_path.start_with?("#{prefix}/")
    end
  end

  def child_active?(n)
    return true if path_active?(n)
    n.children.any? { |child| child_active?(child) }
  end

  def descendant_selected?(n)
    n.children.any? { |child| child.key == @selected_key || descendant_selected?(child) }
  end
end
