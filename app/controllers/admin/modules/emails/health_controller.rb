# frozen_string_literal: true

module Admin
  module Modules
    module Emails
      class HealthController < ApplicationController

        dashboard_menu_item :modules

        def index
          @since, @until_date = ::Emails::Analytics::DateRange.clamp(
            parse_date(params[:since], 30.days.ago).beginning_of_day,
            parse_date(params[:until], Time.current).end_of_day
          )
          @health = ::Emails::Analytics::Health.for(
            current_customer,
            since: @since,
            until_date: @until_date,
            reason: scalar_filter(params[:reason])
          )
        end

        private

        def parse_date(value, default)
          value.present? ? Date.parse(value.to_s) : default
        rescue ArgumentError, TypeError
          default
        end

        def scalar_filter(value)
          Array.wrap(value).find { |v| v.is_a?(String) || v.is_a?(Symbol) }&.to_s.presence
        end
      end
    end
  end
end
