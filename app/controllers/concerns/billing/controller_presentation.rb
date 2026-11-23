# frozen_string_literal: true

module Billing
  # Controllers authorize and scope records before querying presentation facts.
  # The query service owns billing eligibility, snapshots and deadline policy.
  module ControllerPresentation
    extend ActiveSupport::Concern

    private

    def billing_reason_key(reason)
      ::Billing::PresentationFacts.reason_key(reason)
    end

    def billing_usage(customer)
      ::Billing::PresentationFacts.usage(customer: customer)
    end

    def billing_coupon_benefit(subscription, pending_change: nil)
      ::Billing::PresentationFacts.coupon_benefit(subscription: subscription, pending_change: pending_change)
    end

    def billing_subscription_actions(subscription, pending_change:)
      ::Billing::PresentationFacts.subscription_actions(subscription: subscription, pending_change: pending_change)
    end

    def billing_subscription_recovery(subscription, invoices:, entitlements:, actions:)
      ::Billing::PresentationFacts.subscription_recovery(subscription: subscription, invoices: invoices,
                                                        entitlements: entitlements, actions: actions)
    end

    def billing_method_readiness(method, currency:, provider_options:)
      ::Billing::PresentationFacts.method_readiness(payment_method: method, currency: currency,
                                                  provider_options: provider_options)
    end

    def billing_one_time_provider_options(currency)
      ::Billing::PresentationFacts.one_time_provider_options(currency: currency)
    end

    def billing_subscription_one_time_payment(subscription, invoices:)
      ::Billing::PresentationFacts.subscription_one_time_payment(subscription: subscription, invoices: invoices)
    end

    def billing_invoice_collection(invoice, platform: false)
      owner_actions = platform && current_user.platform_owner? &&
                      current_customer_id == ::Billing::Collector::PLATFORM_OWNER_CUSTOMER_ID
      ::Billing::PresentationFacts.invoice_collection(invoice: invoice, owner_actions: owner_actions)
    end

    def billing_invoice_summary(invoices)
      ::Billing::PresentationFacts.invoice_summary(invoices: invoices)
    end

    def billing_tab_counts(customer)
      ::Billing::PresentationFacts.tab_counts(customer: customer)
    end

    def assign_invoice_collection(platform: false)
      billing_filters(statuses: ::Billing::Invoice::STATUSES, platform: platform)
      @collection = billing_invoice_collection(@invoice, platform: platform).merge(@submitted_collection || {})
    end

    def assign_invoice_history_collections(platform: false)
      @collection_by_invoice_id = @invoices.to_h do |invoice|
        [invoice.id, billing_invoice_collection(invoice, platform: platform)]
      end
    end
  end
end
