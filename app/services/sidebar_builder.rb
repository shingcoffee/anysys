# frozen_string_literal: true

class SidebarBuilder
  def self.build(context, menu_item: nil)
    tree = SidebarTree.new
    SidebarContributor.registry.each do |klass|
      klass.new(context).contribute.each do |node|
        next if menu_item && node.menu_item != menu_item
        tree.add(node)
      end
    end
    PermissionFilter.apply(tree, context.current_user)
  end
end
