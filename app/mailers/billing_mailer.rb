# frozen_string_literal: true

# BillingMailer delivers platform billing notifications to the admin user(s) of
# a customer (tenant).
#
# Recipient resolution: the first active admin user for the customer is used.
# If no admin email can be found the mail is silently dropped (returns nil from
# each action and ActionMailer will not enqueue a delivery).
#
# All actions accept the relevant AR object as the sole positional argument so
# that `BillingMailer.invoice_issued(invoice).deliver_later` reads naturally.
class BillingMailer < ApplicationMailer
  PlanLabel = Data.define(:name)
  EXISTING_NOTICE_KINDS = %w[invoice_issued payment_succeeded payment_failed trial_ending subscription_cancelled subscription_past_due].freeze

  def notice(notice)
    @notice = notice
    if EXISTING_NOTICE_KINDS.include?(notice.kind)
      public_send(notice.kind, notice.invoice || notice.subscription)
    else
      @invoice = notice.invoice
      @subscription = notice.subscription
      recipient = notice.kind == "settlement_review" ? owner_email : admin_email_for(notice.customer_id)
      return if recipient.blank?
      assign_links
      billing_mail(to: recipient, subject_key: "billing_mailer.#{notice.kind}.subject", subject_values: { number: @invoice.number },
        body_key: "billing_mailer.#{notice.kind}.body", body_values: { number: @invoice.number, url: notice.kind == "settlement_review" ? @owner_invoice_url : @invoice_url },
        content_type: "text/plain")
    end
  end
  module Timestamps
    def format_mail_date(value)
      return if value.blank?

      I18n.l(value.to_date, format: :long)
    end

    def format_mail_datetime(value)
      return if value.blank?

      I18n.l(value, format: :long)
    end

    def format_mail_period(starts_at, ends_at)
      [format_mail_date(starts_at), format_mail_date(ends_at)].compact.join(" – ")
    end
  end
  helper Timestamps
  include Timestamps
  private :format_mail_date, :format_mail_datetime, :format_mail_period

  # Sent when a new invoice has been finalized and issued.
  def invoice_issued(invoice)
    @invoice      = invoice
    @subscription = invoice.subscription
    @plan         = PlanLabel.new(name: invoice.terms_snapshot.fetch("name"))

    recipient = admin_email_for(invoice.customer_id)
    return if recipient.blank?

    billing_mail(to: recipient, template_name: "invoice_issued", subject_key: "billing_mailer.invoice_issued.subject", subject_values: { number: invoice.number, amount: Billing::CurrencyResolver.format(invoice.total_cents, invoice.currency) })
  end

  # Sent when a payment has been collected successfully.
  def payment_succeeded(invoice)
    @invoice      = invoice
    @subscription = invoice.subscription

    recipient = admin_email_for(invoice.customer_id)
    return if recipient.blank?

    billing_mail(to: recipient, template_name: "payment_succeeded", subject_key: "billing_mailer.payment_succeeded.subject", subject_values: { number: invoice.number })
  end

  # Sent when a payment attempt has failed.
  def payment_failed(invoice)
    @invoice      = invoice
    @subscription = invoice.subscription

    recipient = admin_email_for(invoice.customer_id)
    return if recipient.blank?

    billing_mail(to: recipient, template_name: "payment_failed", subject_key: "billing_mailer.payment_failed.subject", subject_values: { number: invoice.number, attempt: invoice.attempt_count })
  end

  # Sent when a subscription's trial is ending soon.
  def trial_ending(subscription)
    @subscription = subscription
    @plan         = PlanLabel.new(name: subscription.plan_snapshot.fetch("name"))

    recipient = admin_email_for(subscription.customer_id)
    return if recipient.blank?

    billing_mail(to: recipient, template_name: "trial_ending", subject_key: "billing_mailer.trial_ending.subject", subject_values: -> { { date: format_mail_date(subscription.trial_end) } })
  end

  # Sent when a subscription has been cancelled.
  def subscription_cancelled(subscription)
    @subscription = subscription
    @plan         = PlanLabel.new(name: subscription.plan_snapshot.fetch("name"))

    recipient = admin_email_for(subscription.customer_id)
    return if recipient.blank?

    billing_mail(to: recipient, template_name: "subscription_cancelled", subject_key: "billing_mailer.subscription_cancelled.subject")
  end

  # Sent when a subscription transitions to past_due after all dunning retries.
  def subscription_past_due(subscription)
    @subscription = subscription
    @plan         = PlanLabel.new(name: subscription.plan_snapshot.fetch("name"))

    recipient = admin_email_for(subscription.customer_id)
    return if recipient.blank?

    billing_mail(to: recipient, template_name: "subscription_past_due", subject_key: "billing_mailer.subscription_past_due.subject")
  end

  private

  def billing_mail(subject_key:, subject_values: {}, body_key: nil, body_values: {}, **options)
    assign_links
    I18n.with_locale(@subscription.customer.locale.presence || I18n.default_locale) do
      values = subject_values.respond_to?(:call) ? subject_values.call : subject_values
      options[:subject] = t(subject_key, **values)
      options[:body] = t(body_key, **body_values) if body_key
      mail(**options)
    end
  end

  def assign_links
    @billing_url = admin_settings_billing_subscription_url(customer_id: @subscription.customer_id)
    @invoice_url = admin_settings_billing_invoice_url(customer_id: @invoice.customer_id, id: @invoice.id) if @invoice
    @owner_invoice_url = admin_maintenance_platform_billing_invoice_url(customer_id: Billing::Collector::PLATFORM_OWNER_CUSTOMER_ID, id: @invoice.id) if @invoice
  end

  def owner_email
    Authentication::User.unscoped.where(customer_id: Billing::Collector::PLATFORM_OWNER_CUSTOMER_ID, status: :active).by_role(:owner).pick(:email)
  end

  # Returns the email address of the first active admin user for the given
  # customer, or nil if none exists (e.g. the customer has no admin yet).
  def admin_email_for(customer_id)
    Authentication::User
      .unscoped
      .where(customer_id: customer_id, status: :active)
      .by_role(:admin)
      .pick(:email)
  end
end
