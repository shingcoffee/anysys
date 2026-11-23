# frozen_string_literal: true

module Emails
  class ReportsComponent < ApplicationComponent
    attr_reader :report, :since, :until_date, :csv_path, :url

    def initialize(report:, since:, until_date:, csv_path:, url:)
      @report     = report
      @since      = since
      @until_date = until_date
      @csv_path   = csv_path
      @url        = url
    end

    def totals
      report[:totals]
    end

    def daily
      report[:daily]
    end

    def send_activities
      report[:send_activities]
    end

    def current_customer_id
      helpers.current_customer_id
    end

    def send_activity_names
      @send_activity_names ||= Emails::SendActivities::SendActivity.where(customer_id: current_customer_id, id: send_activities.keys).pluck(:id, :name).to_h
    end

    def sparkline_values(metric)
      daily.map { |d| d[metric] }
    end

    def any_data?
      totals.values.any?(&:positive?) || daily.any? { |d| d.except(:date).values.any?(&:positive?) }
    end

    def empty?(collection)
      collection.blank?
    end
  end
end
