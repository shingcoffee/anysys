# frozen_string_literal: true

module Emails
  class DeliverabilityComponent < ApplicationComponent
    attr_reader :since, :until_date, :totals, :failure_breakdown, :suppressions

    def initialize(since:, until_date:, totals:, failure_breakdown:, suppressions:)
      @since             = since
      @until_date        = until_date
      @totals            = totals
      @failure_breakdown = failure_breakdown
      @suppressions      = suppressions
    end

    def empty?(collection)
      collection.blank?
    end
  end
end
