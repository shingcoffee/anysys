# frozen_string_literal: true

module Billing
  class DispatchNoticeJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 8

    def perform(notice_id)
      notice = Notice.unscoped_by_tenant.find(notice_id)
      Billing::Result.transaction(notice) do
        next unless notice.state == "pending"
        Current.set(customer: notice.customer) do
          I18n.with_locale(notice.customer.locale.presence || I18n.default_locale) do
            # This is the committed outbox worker, never the business transaction.
            # SMTP cannot promise exactly-once after a crash following acceptance.
            BillingMailer.notice(notice).deliver_now
          end
        end
        notice.update!(state: "enqueued", enqueued_at: Time.current)
      end
    end
  end
end
