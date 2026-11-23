# frozen_string_literal: true

# Icon rail shown when the desktop sidebar is collapsed. Leaf destinations
# stay one click away. A grouped section, such as a Settings module, is one
# icon that opens the full sidebar so its children remain reachable. Plain
# section labels become quiet dividers.
class SidebarRailComponent < ApplicationComponent
  Entry = Struct.new(:kind, :node, :active, keyword_init: true)

  def initialize(tree:, menu_item:, current_path:)
    @tree = tree
    @menu_item = menu_item
    @current_path = current_path.to_s
  end

  attr_reader :tree, :menu_item, :current_path

  def section_label
    MenuRegistry.item(menu_item)&.label || menu_item.to_s
  end

  # Searchable menus keep search one click away: the rail control opens the
  # full sidebar with its search field focused.
  def search?
    sidebar.searchable? && entries.any?
  end

  def search_label
    sidebar.search_placeholder
  end

  def entries
    return @entries if @entries

    selected = SidebarNodeComponent.selected_key(sidebar.nodes, current_path)
    built = []

    separate = -> { built << Entry.new(kind: :separator) if built.any? && built.last.kind != :separator }

    sidebar.categories.each do |category|
      separate.call if category[:label]
      category[:groups].each do |group|
        if sidebar.sectioned? && group[:header]
          node = group[:header].with_children(group[:nodes])
          built << Entry.new(kind: :group, node: node, active: active_tree?(node, selected))
        else
          separate.call if group[:header]
          group[:nodes].each do |node|
            if node.children.any?
              built << Entry.new(kind: :group, node: node, active: active_tree?(node, selected))
            elsif node.link?
              built << Entry.new(kind: :link, node: node, active: node.key == selected)
            end
          end
        end
      end
    end

    built.pop while built.last&.kind == :separator
    @entries = built
  end

  def monogram(label)
    label.to_s.strip.grapheme_clusters.first.to_s.upcase
  end

  def glyph_for(node)
    if node.icon.present?
      helpers.tag.svg(
        helpers.tag.path(d: node.icon),
        class: "size-[18px] shrink-0", viewBox: "0 0 24 24", fill: "none",
        stroke: "currentColor", "stroke-width": "1.5", "stroke-linecap": "round",
        "stroke-linejoin": "round", "aria-hidden": "true"
      )
    else
      helpers.tag.span(monogram(node.label), class: "text-[11px] font-semibold leading-none", "aria-hidden": "true")
    end
  end

  def icon_classes(active)
    state = if active
              "bg-accent-subtle text-accent"
            else
              "text-text-muted hover:bg-surface-hover hover:text-text-primary"
            end
    "flex size-9 shrink-0 items-center justify-center rounded-lg transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent #{state}"
  end

  private

  def sidebar
    @sidebar ||= SidebarComponent.new(tree: tree, menu_item: menu_item, current_path: current_path)
  end

  def active_tree?(node, selected)
    return false if selected.nil?

    node.key == selected || node.children.any? { |child| active_tree?(child, selected) }
  end
end
