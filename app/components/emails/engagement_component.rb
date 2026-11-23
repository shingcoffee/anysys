# frozen_string_literal: true

module Emails
  class EngagementComponent < ApplicationComponent
    attr_reader :since, :until_date, :top_links, :opens_by_hour, :opens_by_day, :devices

    def initialize(since:, until_date:, top_links:, opens_by_hour:, opens_by_day:, devices:)
      @since         = since
      @until_date    = until_date
      @top_links     = top_links
      @opens_by_hour = opens_by_hour
      @opens_by_day  = opens_by_day
      @devices       = devices
    end

    def sparkline_values
      opens_by_day.sort_by { |day, _| day.to_s }.map { |_, count| count }
    end

    def empty?(collection)
      collection.blank?
    end
  end
end
