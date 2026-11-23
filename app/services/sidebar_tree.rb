# frozen_string_literal: true

class SidebarTree
  def initialize
    @buckets = SidebarNode::MENU_ITEMS.each_with_object({}) { |m, h| h[m] = [] }
  end

  def add(node)
    @buckets[node.menu_item] << node
    self
  end

  def nodes_for(menu_item)
    @buckets.fetch(menu_item, [])
  end

  def all
    @buckets
  end

  def replace(menu_item, nodes)
    @buckets[menu_item] = nodes
    self
  end
end
