# frozen_string_literal: true

class DrawerComponent < ApplicationComponent
  def initialize(customer:, tree:, menu_items:, current_menu_item:, current_path:)
    @customer = customer
    @tree = tree
    @menu_items = menu_items || []
    @current_menu_item = current_menu_item
    @current_path = current_path
  end

  attr_reader :customer, :tree, :menu_items, :current_menu_item, :current_path

  def item_path(item) = item.path_for(customer)

  def active_item?(item)
    item.key == active_key
  end

  private

  def active_key
    @active_key ||= menu_items.find { |item| item.active_for?(customer, current_path) }&.key || current_menu_item
  end
end
