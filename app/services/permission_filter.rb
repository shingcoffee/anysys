# frozen_string_literal: true

class PermissionFilter
  def self.apply(tree, user)
    filtered = SidebarTree.new
    tree.all.each_key do |section|
      kept = tree.nodes_for(section).filter_map { |n| keep(n, user) }
      filtered.replace(section, kept)
    end
    filtered
  end

  def self.keep(node, user)
    return nil unless node.permitted_for?(user)

    visible_children = node.children.filter_map { |c| keep(c, user) }
    return node.with_children(visible_children) if node.link? || visible_children.any?
    # A permitted, originally-childless node (e.g. a section placeholder) is kept.
    # A parent whose children all got filtered away becomes a "ghost" — drop it.
    return node if node.children.empty?

    nil
  end
  private_class_method :keep
end
