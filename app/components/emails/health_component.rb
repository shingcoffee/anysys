# frozen_string_literal: true

module Emails
  class HealthComponent < ApplicationComponent
    attr_reader :health, :since, :until_date, :url

    def initialize(health:, since:, until_date:, url:)
      @health = health
      @since = since
      @until_date = until_date
      @url = url
    end

    def empty?(collection)
      collection.blank?
    end

    def sparkline_values
      health[:opens_by_day].sort_by { |day, _| day.to_s }.map(&:last)
    end
  end
end
