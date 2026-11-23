# frozen_string_literal: true

# Panel body for the admin-chrome notifications bell: inbox rows or the
# compact empty state. Root id is the historical turbo body target.
class NotificationsInboxComponent < ApplicationComponent
  PANEL_BODY_DOM_ID = "notifications-panel-body"
  LIST_DOM_ID = "notifications-inbox-list"
  EMPTY_DOM_ID = "notifications-inbox-empty"

  def initialize(items:, mark_read_path:, support_ticket_read_path: nil)
    @items          = items
    @mark_read_path = mark_read_path
    @support_ticket_read_path  = support_ticket_read_path
  end

  attr_reader :items, :mark_read_path, :support_ticket_read_path

  def panel_body_dom_id = PANEL_BODY_DOM_ID
  def list_dom_id = LIST_DOM_ID
  def empty_dom_id = EMPTY_DOM_ID

  def empty? = items.empty?
end
