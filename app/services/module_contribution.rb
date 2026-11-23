# frozen_string_literal: true

class ModuleContribution
  attr_reader :label, :entry_key, :path, :icon, :badge, :permitted_by, :children, :match_prefix

  # match_prefix: optional String or Array<String> of additional path prefixes that should
  # also mark this entry active (e.g. sibling in-page tabs sharing one sidebar entry).
  def initialize(label:, entry_key:, path: nil, icon: nil, badge: nil, permitted_by: nil, children: [], match_prefix: nil)
    @label = label
    @entry_key = entry_key
    @path = path
    @icon = icon
    @badge = badge
    @permitted_by = permitted_by
    @children = children
    @match_prefix = match_prefix
  end

  def to_sidebar_node(menu_item:, module_key:, customer_id:)
    resolved = children.any? ? nil : resolved_path(menu_item, module_key, customer_id)
    SidebarNode.new(
      key: "#{menu_item}.#{module_key}.#{entry_key}",
      label: label,
      menu_item: menu_item,
      path: resolved,
      icon: icon,
      badge: badge,
      permitted_by: permitted_by,
      match_prefix: match_prefix.nil? ? resolved : match_prefix,
      children: children.map { |c|
        c.to_sidebar_node(menu_item: menu_item, module_key: module_key, customer_id: customer_id)
      }
    )
  end

  def href_for(customer_id:, menu_item:, module_key:)
    resolved_path(menu_item, module_key, customer_id)
  end

  private

  def resolved_path(menu_item, module_key, customer_id)
    return path.call(customer_id) if path.respond_to?(:call)
    path || default_path(menu_item, module_key, customer_id)
  end

  def default_path(menu_item, module_key, customer_id)
    segment = module_key.to_s.pluralize
    case menu_item
    when :modules  then "/#{customer_id}/admin/modules/#{segment}/entries/#{entry_key}"
    when :settings then "/#{customer_id}/admin/settings/modules/#{segment}/#{entry_key}"
    end
  end
end
