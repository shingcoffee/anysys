# frozen_string_literal: true

module Notifications
  # Unified admin-chrome bell: platform announcements plus help tickets.
  class Inbox
    include Rails.application.routes.url_helpers

    Item = Struct.new(
      :kind, :id, :title, :body, :unread, :occurred_at, :href, :subtitle,
      :link_url, :mark_read_param, :mark_read_value,
      keyword_init: true
    )

    LIMIT = 50

    def self.for_viewer(user:, customer_id:, now: Time.current)
      new(user: user, customer_id: customer_id, now: now).items
    end

    def initialize(user:, customer_id:, now: Time.current)
      @user = user
      @customer_id = customer_id
      @now = now
    end

    def items
      (announcement_items + help_items)
        .sort_by { |item| [ item.unread ? 0 : 1, -(item.occurred_at&.to_i || 0), -item.id.to_i ] }
        .first(LIMIT)
    end

    def visible_support_ticket(id)
      return nil if id.blank? || user.blank?

      request = help_scope.includes(:messages).find_by(id: id)
      return nil if request.blank? || request.latest_message.blank?

      request
    end

    def thread_path_for(request)
      help_href(request)
    end

    private

    attr_reader :user, :customer_id, :now

    def announcement_items
      return [] if user.blank? || customer_id.blank?

      inbox = PlatformAnnouncements::InboxResolver.for_viewer(user: user, customer_id: customer_id, now: now)
      read_ids = inbox.read_ids.to_set
      inbox.announcements.map do |row|
        Item.new(
          kind: :announcement,
          id: row.id,
          title: row.title,
          body: row.body_for(I18n.locale),
          unread: read_ids.exclude?(row.id),
          occurred_at: row.created_at,
          href: nil,
          subtitle: nil,
          link_url: row.link_url.presence,
          mark_read_param: :platform_announcement_id,
          mark_read_value: row.id
        )
      end
    end

    def help_items
      return [] if user.blank?

      requests = help_scope.includes(:messages, :reads, :user, :customer).newest_first.limit(LIMIT).to_a
      requests.filter_map { |request| help_item(request) }
    end

    def help_scope
      visible = SupportTicket.unscoped_by_tenant.inbox_visible(now)
      if user.platform_owner?
        visible
      else
        visible.where(customer_id: customer_id, user_id: user.id)
      end
    end

    def help_item(request)
      latest = request.latest_message
      return nil if latest.blank?

      Item.new(
        kind: :support_ticket,
        id: request.id,
        title: request.subject,
        body: latest.body,
        unread: support_ticket_unread?(request),
        occurred_at: request.last_message_at,
        href: help_href(request),
        subtitle: help_subtitle(request),
        link_url: nil,
        mark_read_param: :support_ticket_id,
        mark_read_value: request.id
      )
    end

    def support_ticket_unread?(request)
      request.unread_for?(user)
    end

    def help_href(request)
      if user.platform_owner?
        admin_maintenance_platform_support_ticket_path(
          Authentication::User::PLATFORM_CUSTOMER_ID, request
        )
      else
        admin_support_ticket_path(request.customer_id, request)
      end
    end

    def help_subtitle(request)
      return nil unless user.platform_owner?

      request.customer&.name
    end
  end
end
