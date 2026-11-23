# frozen_string_literal: true

module Billing
  class Notice < ApplicationRecord
    self.table_name = "billing_notices"
    include TenantScoped
    belongs_to :invoice, class_name: "Billing::Invoice", foreign_key: :billing_invoice_id, optional: true
    belongs_to :subscription, class_name: "Billing::Subscription", foreign_key: :billing_subscription_id, optional: true
    belongs_to :collection_attempt, class_name: "Billing::CollectionAttempt", foreign_key: :billing_collection_attempt_id, optional: true
    validates :customer_id, :event_key, :kind, presence: true
    validates :state, inclusion: { in: %w[pending enqueued] }
    after_create_commit :dispatch

    private

    def dispatch
      Billing::DispatchNoticeJob.perform_later(id)
    rescue ActiveJob::EnqueueError => error
      Rails.logger.error("[billing.notice] id=#{id} #{error.class}")
    end
  end
end
