# frozen_string_literal: true

class SidebarComponent < ApplicationComponent
  SEARCHABLE_MENU_ITEMS = %i[settings modules].freeze
  # Settings and Modules hand tablet widths to their own navigation sheet, so
  # their full sidebar only appears from the `lg` breakpoint.
  DESKTOP_ONLY_MENU_ITEMS = %i[settings modules].freeze

  attr_reader :tree, :menu_item, :current_path, :mobile, :search_id

  def initialize(tree:, menu_item:, current_path:, mobile: false, search_id: "sidebar-settings-search", collapsible: false)
    @tree = tree
    @menu_item = menu_item
    @current_path = current_path
    @mobile = mobile
    @search_id = search_id
    @collapsible = collapsible
  end

  def nodes
    tree.nodes_for(menu_item)
  end

  def searchable?
    SEARCHABLE_MENU_ITEMS.include?(menu_item)
  end

  def aside_classes
    width = if mobile then "flex w-full flex-col"
            elsif DESKTOP_ONLY_MENU_ITEMS.include?(menu_item) then "hidden lg:flex lg:w-72 lg:flex-col shrink-0"
            else "hidden md:flex md:flex-col w-60 lg:w-64 xl:w-72 shrink-0"
            end
    "#{width} min-h-0 bg-surface border-r border-border"
  end

  # The shell's collapsible wrapper mirrors the desktop widths above while
  # expanded, so its width can animate between two explicit values.
  def self.expanded_shell_classes(menu_item)
    if DESKTOP_ONLY_MENU_ITEMS.include?(menu_item)
      "data-[state=expanded]:lg:flex data-[state=expanded]:lg:w-72"
    else
      "data-[state=expanded]:md:flex data-[state=expanded]:w-60 data-[state=expanded]:lg:w-64 data-[state=expanded]:xl:w-72"
    end
  end

  # Settings contributes flat section headings for its catalog. The sidebar
  # wraps each heading's links in the same disclosure used by Modules.
  def sectioned?
    menu_item == :settings
  end

  def nav_label
    I18n.t("chrome.menu_bar.items.#{menu_item}")
  end

  def collapsible?
    @collapsible
  end

  # The registered top-menu label wins; menu items outside the registry fall back to the nav label.
  def section_label
    MenuRegistry.item(menu_item)&.label || nav_label
  end

  # A category heading (e.g. "Communication") starts a run of groups until the
  # next heading. Nodes before the first heading form an unlabeled category,
  # so menus without headings render as a single list.
  def categories
    @categories ||= nodes.slice_before(&:category?).filter_map do |chunk|
      label = chunk.first.category? ? chunk.first : nil
      groups = group(label ? chunk.drop(1) : chunk)
      { label: label, groups: groups } if groups.any?
    end
  end

  def grouped_nodes
    categories.flat_map { |category| category[:groups] }
  end

  def list_gap_class
    return "gap-5" if categories.any? { |category| category[:label] }

    sectioned? ? "gap-0.5" : "gap-4"
  end

  def category_label_id(category)
    "#{search_id}-#{category[:label].key.parameterize}"
  end

  def search_placeholder
    return I18n.t("chrome.sidebar.search_placeholder") if menu_item == :settings

    I18n.t("chrome.sidebar.search_in", name: nav_label)
  end

  def search_empty_title
    I18n.t("chrome.sidebar.search_empty_titles.#{menu_item}", default: I18n.t("chrome.sidebar.search_empty_title"))
  end

  def selected_key
    @selected_key ||= SidebarNodeComponent.selected_key(nodes, current_path)
  end

  private

  # Split a flat contributor list into labeled groups. A `section_root` node
  # with no path and no children is a group label (GitHub/Stripe settings nav);
  # everything after it belongs to that group until the next label.
  def group(list)
    groups = []
    current = { header: nil, nodes: [] }

    list.each do |node|
      if section_label?(node)
        groups << current if current[:header] || current[:nodes].any?
        current = { header: node, nodes: [] }
      else
        current[:nodes] << node
      end
    end
    groups << current if current[:header] || current[:nodes].any?
    sectioned? ? groups.reject { |group| group[:nodes].empty? } : groups
  end

  def section_label?(node)
    node.section_root && !node.link? && node.children.empty?
  end
end
