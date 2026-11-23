# frozen_string_literal: true

module Notifications
  # Per-user signed Turbo Stream for the admin-chrome bell. The shell
  # subscribes with turbo_stream_from. The stream name is only the user id
  # so an owner tab on any tenant still receives help-ticket updates.
  # Announcement pushes go only to tenant admins of matching customers —
  # never the platform owner — so a tenant-scoped banner/row cannot land
  # on the wrong act-as tab.
  module Stream
    SUPPORT_TICKET_UNREAD_ID = "notifications-support-ticket-unread"
    ANNOUNCEMENT_UNREAD_ID = "notifications-announcement-unread"

    def self.name(user_id:)
      [ :notifications, user_id ]
    end

    def self.broadcast_help!(request:, message:)
      recipients_for(request, message).each do |recipient|
        broadcast_help_to_user!(recipient, request: request, message: message)
      rescue StandardError => e
        Rails.logger.error("Notifications::Stream broadcast failed user=#{recipient.id}: #{e.class}: #{e.message}")
      end
    end

    def self.broadcast_announcement!(announcement)
      return unless announcement.live?

      announcement_recipients(announcement).each do |recipient|
        broadcast_announcement_to_user!(recipient, announcement: announcement)
      rescue StandardError => e
        Rails.logger.error("Notifications::Stream announcement broadcast failed user=#{recipient.id}: #{e.class}: #{e.message}")
      end
    end

    def self.broadcast_announcement_removed!(announcement, users:)
      Array(users).each do |recipient|
        broadcast_announcement_removed_to_user!(recipient, announcement: announcement)
      rescue StandardError => e
        Rails.logger.error("Notifications::Stream announcement removal failed user=#{recipient.id}: #{e.class}: #{e.message}")
      end
    end

    # Ended notices remain in bell history while leaving the banner. Reuse the
    # same per-user fragments, locale and tenant scoping as owner-driven edits.
    def self.refresh_announcement!(announcement)
      broadcast_announcement_removed!(announcement, users: announcement_recipients(announcement).to_a)
    end

    def self.sync_announcement!(announcement, previous_users: [])
      current = announcement.live? ? announcement_recipients(announcement).to_a : []
      if announcement.live?
        broadcast_announcement!(announcement)
        gone = previous_users.reject { |user| current.any? { |row| row.id == user.id } }
        broadcast_announcement_removed!(announcement, users: gone)
      else
        broadcast_announcement_removed!(announcement, users: previous_users)
      end
      Notifications::BroadcastAnnouncementJob.schedule(announcement)
    end

    def self.announcement_recipients(announcement)
      customer_ids = announcement_customer_ids(announcement)
      return Authentication::User.none if customer_ids.blank?

      Authentication::User.unscoped_by_tenant.active.by_role(:admin).where(customer_id: customer_ids)
    end

    def self.support_ticket_unread_html(count)
      unread_span(SUPPORT_TICKET_UNREAD_ID, "supportTicketUnread", count)
    end

    def self.announcement_unread_html(count)
      unread_span(ANNOUNCEMENT_UNREAD_ID, "announcementUnread", count)
    end

    def self.unread_span(dom_id, target, count)
      %(<span id="#{dom_id}" data-notifications-menu-target="#{target}" data-count="#{count.to_i}" hidden></span>).html_safe
    end
    private_class_method :unread_span

    def self.recipients_for(request, message)
      case message.author_role
      when "requester"
        Array(platform_owner).compact
      when "owner"
        Array(request.user)
      else
        []
      end.reject { |user| user.id == message.user_id }
    end
    private_class_method :recipients_for

    def self.platform_owner
      Authentication::User.unscoped_by_tenant.find_by(
        customer_id: Authentication::User::PLATFORM_CUSTOMER_ID,
        email: Authentication::User::PLATFORM_OWNER_EMAIL
      )
    end
    private_class_method :platform_owner

    def self.announcement_customer_ids(announcement)
      if announcement.all_customers?
        Customer.active.ids
      else
        announcement.matching_customers.ids
      end
    end
    private_class_method :announcement_customer_ids

    def self.broadcast_help_to_user!(user, request:, message:)
      locale = user.locale.presence || I18n.default_locale
      I18n.with_locale(locale) { broadcast_help_fragments!(user, request: request, message: message) }
    end
    private_class_method :broadcast_help_to_user!

    def self.broadcast_help_fragments!(user, request:, message:)
      customer_id = render_customer_id(user, request)
      inbox = Inbox.new(user: user, customer_id: customer_id)
      item = inbox.items.find { |row| row.kind == :support_ticket && row.id == request.id }
      return if item.blank?

      stream = name(user_id: user.id)
      bell = NotificationsButtonComponent.new(user: user, customer_id: customer_id)
      support_ticket_read_path = Rails.application.routes.url_helpers.admin_support_ticket_reads_path(customer_id)
      mark_read_path = Rails.application.routes.url_helpers.admin_platform_announcement_reads_path(customer_id)

      Turbo::StreamsChannel.broadcast_replace_to(
        stream, target: SUPPORT_TICKET_UNREAD_ID, html: support_ticket_unread_html(bell.support_ticket_unread_count)
      )
      Turbo::StreamsChannel.broadcast_remove_to(
        stream, target: NotificationsInboxRowComponent.dom_id_for(request.id)
      )
      Turbo::StreamsChannel.broadcast_prepend_to(
        stream,
        target: NotificationsInboxComponent::LIST_DOM_ID,
        html: ApplicationController.render(
          NotificationsInboxRowComponent.new(
            item: item, mark_read_path: mark_read_path, support_ticket_read_path: support_ticket_read_path
          ),
          layout: false
        )
      )
      Turbo::StreamsChannel.broadcast_append_to(
        stream,
        target: HelpThreadComponent.messages_dom_id(request.id),
        html: ApplicationController.render(
          HelpMessageBubbleComponent.new(message: message, viewer: user),
          layout: false
        )
      )
    end
    private_class_method :broadcast_help_fragments!

    def self.broadcast_announcement_to_user!(user, announcement:)
      customer_id = user.customer_id
      stream = name(user_id: user.id)
      locale = user.locale.presence || I18n.default_locale

      I18n.with_locale(locale) do
        bell = NotificationsButtonComponent.new(user: user, customer_id: customer_id)
        Turbo::StreamsChannel.broadcast_replace_to(
          stream, target: ANNOUNCEMENT_UNREAD_ID, html: announcement_unread_html(bell.announcement_unread_count)
        )

        item = bell.inbox_items.find { |row| row.kind == :announcement && row.id == announcement.id }
        Turbo::StreamsChannel.broadcast_remove_to(
          stream, target: NotificationsInboxRowComponent.announcement_dom_id_for(announcement.id)
        )
        if item
          mark_read_path = Rails.application.routes.url_helpers.admin_platform_announcement_reads_path(customer_id)
          support_ticket_read_path = Rails.application.routes.url_helpers.admin_support_ticket_reads_path(customer_id)
          Turbo::StreamsChannel.broadcast_prepend_to(
            stream,
            target: NotificationsInboxComponent::LIST_DOM_ID,
            html: ApplicationController.render(
              NotificationsInboxRowComponent.new(
                item: item, mark_read_path: mark_read_path, support_ticket_read_path: support_ticket_read_path
              ),
              layout: false
            )
          )
        end

        Turbo::StreamsChannel.broadcast_replace_to(
          stream,
          target: Platform::AnnouncementBannerComponent::STACK_DOM_ID,
          html: ApplicationController.render(
            Platform::AnnouncementBannerComponent.new(user: user, customer_id: customer_id),
            layout: false
          )
        )
      end
    end
    private_class_method :broadcast_announcement_to_user!

    def self.broadcast_announcement_removed_to_user!(user, announcement:)
      broadcast_announcement_to_user!(user, announcement: announcement)
    end
    private_class_method :broadcast_announcement_removed_to_user!

    def self.render_customer_id(user, request)
      user.platform_owner? ? Authentication::User::PLATFORM_CUSTOMER_ID : request.customer_id
    end
    private_class_method :render_customer_id
  end
end
