# frozen_string_literal: true

class HelpMenuComponent < ApplicationComponent
  ITEM_CLASSES = "w-full flex items-start gap-3 rounded-lg px-3 py-2.5 text-sm hover:bg-surface-hover transition-base group"

  def initialize(user: nil, customer_id: nil)
    @user = user
    @customer_id = customer_id
  end

  def show_notify?
    user.present? && !user.platform_owner? && customer_id.present?
  end

  def show_docs?
    user&.admin_or_owner? && customer_id.present?
  end

  def docs_url
    return unless show_docs?

    helpers.admin_help_docs_path(customer_id, locale: I18n.locale)
  end

  def notify_path
    return if customer_id.blank?

    helpers.admin_support_tickets_path(customer_id)
  end

  def email_path
    return if customer_id.blank?

    helpers.admin_help_emails_path(customer_id)
  end

  private

  attr_reader :user, :customer_id
end
