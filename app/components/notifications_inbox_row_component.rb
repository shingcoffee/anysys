# frozen_string_literal: true

class NotificationsInboxRowComponent < ApplicationComponent
  TITLE_LIMIT = 56
  BODY_LIMIT = 100

  ICON_WELL_CLASSES = {
    announcement: "bg-accent-subtle text-accent ring-accent-muted/60",
    support_ticket: "bg-info-subtle text-info ring-info/20"
  }.freeze

  KIND_LABEL_CLASSES = {
    announcement: "text-accent-text",
    support_ticket: "text-info"
  }.freeze

  def self.dom_id_for(id)
    "notifications-support-ticket-row-#{id}"
  end

  def self.announcement_dom_id_for(id)
    "notifications-announcement-row-#{id}"
  end

  def initialize(item:, mark_read_path:, support_ticket_read_path: nil)
    @item = item
    @mark_read_path = mark_read_path
    @support_ticket_read_path = support_ticket_read_path
  end

  attr_reader :item, :mark_read_path, :support_ticket_read_path

  def unread? = item.unread

  def announcement?
    item.kind == :announcement
  end

  def support_ticket?
    item.kind == :support_ticket
  end

  def preview
    item.body.to_s.squish
  end

  def title
    item.title.to_s.squish
  end

  def kind_label
    I18n.t("chrome.notifications.kinds.#{item.kind}")
  end

  def learn_more?
    announcement? && item.link_url.present?
  end

  def learn_more_url
    item.link_url
  end

  def row_dom_id
    if support_ticket?
      self.class.dom_id_for(item.id)
    elsif announcement?
      self.class.announcement_dom_id_for(item.id)
    end
  end

  def occurred_label
    return if item.occurred_at.blank?

    distance = helpers.time_ago_in_words(item.occurred_at)
    future   = item.occurred_at.to_time > Time.current
    I18n.t("chrome.admin_table.#{future ? "time_in" : "time_ago"}", time: distance)
  end

  def row_classes
    base = "group relative flex items-start gap-3 px-4 py-3 transition-base hover:bg-surface-hover " \
           "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-accent"
    unread? ? "#{base} bg-accent-subtle/40" : base
  end

  def title_classes
    tone = unread? ? "font-semibold text-text-primary" : "font-medium text-text-secondary"
    "block min-w-0 text-sm leading-5 break-words #{tone}"
  end

  def preview_classes
    tone = unread? ? "text-text-secondary" : "text-text-tertiary"
    "mt-0.5 block text-xs leading-5 break-words whitespace-pre-wrap #{tone}"
  end

  def icon_well_classes
    "flex size-9 shrink-0 items-center justify-center rounded-full ring-1 ring-inset #{ICON_WELL_CLASSES.fetch(item.kind)}"
  end

  def kind_label_classes
    "font-medium #{KIND_LABEL_CLASSES.fetch(item.kind)}"
  end
end
