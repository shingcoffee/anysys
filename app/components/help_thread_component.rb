# frozen_string_literal: true

class HelpThreadComponent < ApplicationComponent
  def self.messages_dom_id(request_id)
    "support-ticket-messages-#{request_id}"
  end

  def initialize(support_ticket:, messages:, viewer:, reply_path:, resolve_path: nil, owner_view: false)
    @support_ticket = support_ticket
    @messages = messages
    @viewer = viewer
    @reply_path = reply_path
    @resolve_path = resolve_path
    @owner_view = owner_view
  end

  attr_reader :support_ticket, :messages, :viewer, :reply_path, :resolve_path

  def owner_view? = @owner_view

  def can_reply? = support_ticket.open?

  def can_resolve? = owner_view? && resolve_path.present? && can_reply?

  def messages_dom_id
    self.class.messages_dom_id(support_ticket.id)
  end

  def reply_stimulus_data
    Help::AttachmentRules.stimulus_data(accept: Help::AttachmentRules.image_accept)
  end

  def created_label
    I18n.l(support_ticket.created_at, format: :short)
  end

  def last_message_label
    stamp = support_ticket.last_message_at || support_ticket.created_at
    I18n.l(stamp, format: :short)
  end

  def messages_count_label
    @messages_count_label ||= I18n.t("chrome.help_menu.thread.messages_count", count: messages.size)
  end

  def requester_name
    support_ticket.user&.display_name
  end

  def requester_email
    support_ticket.user&.email
  end

  def requester_initials
    letters_from(requester_name)
  end

  def customer_name
    support_ticket.customer&.name
  end

  def customer_id_label
    support_ticket.customer_id.to_s
  end

  def show_act_as?
    return false unless owner_view?

    cid = support_ticket.customer_id
    return false if cid.blank?
    return false if cid.to_s == Authentication::User::PLATFORM_CUSTOMER_ID.to_s

    Current.acting_as_customer&.id != cid
  end

  def act_as_path
    return unless show_act_as?

    helpers.admin_dashboard_path(support_ticket.customer_id)
  end

  def status_badge
    if support_ticket.open?
      { variant: :info, label: I18n.t("help.status.open") }
    else
      { variant: :default, label: I18n.t("help.status.resolved") }
    end
  end

  private

  def letters_from(name)
    parts = name.to_s.strip.split(/\s+/).reject(&:blank?)
    if parts.size >= 2
      "#{parts.first[0]}#{parts.last[0]}".upcase
    else
      name.to_s.gsub(/[^\p{L}\p{N}]/, "")[0, 2].upcase.presence || "?"
    end
  end
end
