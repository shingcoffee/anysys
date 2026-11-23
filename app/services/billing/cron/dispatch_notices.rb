# frozen_string_literal: true

module Billing
  module Cron
    class DispatchNotices
      def self.perform
        Notice.unscoped_by_tenant.where(state: "pending").find_each { |notice| DispatchNoticeJob.perform_later(notice.id) }
      end
    end
  end
end
