# frozen_string_literal: true

module Admin
  module Modules
    module Emails
      class DashboardController < ApplicationController

        dashboard_menu_item :modules

        def show
          @since, @until_date = ::Emails::Analytics::DateRange.clamp(
            parse_date(params[:since], 30.days.ago).beginning_of_day,
            parse_date(params[:until], Time.current).end_of_day
          )
          @stats = ::Emails::DashboardStats.for(current_customer, since: @since, until_date: @until_date)
          @report = ::Emails::Analytics::Report.for(current_customer, since: @since, until_date: @until_date)
          @send_activity_names = ::Emails::SendActivities::SendActivity.where(
            customer_id: current_customer.id,
            id: @report[:send_activities].keys
          ).pluck(:id, :name).to_h

          respond_to do |format|
            format.html
            format.csv { send_data ::Emails::Analytics::ExportCsv.call(filtered_messages), filename: "email-report.csv" }
          end
        end

        private

        def parse_date(value, default)
          value.present? ? Date.parse(value.to_s) : default
        rescue ArgumentError, TypeError
          default
        end

        def filtered_messages
          ::Emails::Message.for_current_customer.where(created_at: @since..@until_date)
        end
      end
    end
  end
end
