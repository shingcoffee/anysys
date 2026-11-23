# frozen_string_literal: true

class SidebarNode
  MENU_ITEMS = %i[home assistant entities pages modules settings maintenance].freeze

  attr_reader :key, :label, :path, :icon, :badge, :menu_item, :children,
              :permitted_by, :section_root, :match_prefix, :match_paths, :description,
              :category, :tone, :monogram

  # `category` marks a non-interactive heading that starts a group of sections
  # (e.g. "Communication"). `tone` names the colors that tint the node's icon
  # tile (see SidebarTone). `monogram` fills the tile when there is no icon.
  def initialize(key:, label:, menu_item:, path: nil, icon: nil, badge: nil,
                 children: [], permitted_by: nil, section_root: false, match_prefix: nil,
                 description: nil, match_paths: [], category: false, tone: nil,
                 monogram: nil)
    unless MENU_ITEMS.include?(menu_item)
      raise ArgumentError, "menu_item must be one of #{MENU_ITEMS}"
    end
    @key = key
    @label = label
    @menu_item = menu_item
    @path = path
    @icon = icon
    @badge = badge
    @children = children
    @permitted_by = permitted_by
    @section_root = section_root
    @match_prefix = match_prefix
    @match_paths = Array(match_paths)
    @description = description
    @category = category
    @tone = tone
    @monogram = monogram
  end

  def link?
    !path.nil? && !path.empty?
  end

  def category?
    @category
  end

  def permitted_for?(user)
    case permitted_by
    when nil    then true
    when Proc   then permitted_by.call(user)
    when Symbol then user.respond_to?(permitted_by) && user.public_send(permitted_by)
    else false
    end
  end

  def with_children(new_children)
    with(children: new_children)
  end

  # Copy with selected attributes replaced — keeps the value object immutable.
  def with(**overrides)
    attrs = {
      key: key, label: label, menu_item: menu_item, path: path, icon: icon,
      badge: badge, children: children, permitted_by: permitted_by,
      section_root: section_root, match_prefix: match_prefix, match_paths: match_paths,
      description: description, category: category, tone: tone,
      monogram: monogram
    }.merge(overrides)
    SidebarNode.new(**attrs)
  end
end
