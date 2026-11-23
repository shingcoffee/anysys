# frozen_string_literal: true

module Payments
  module Admin
    # Renders the platform-owner ledger of inbound PSP webhook events with a
    # redrive button for stranded (received/failed) records. Used by the platform
    # webhook-events index page.
    class WebhookEventTableComponent < ApplicationComponent
      def initialize(events:)
        @events = events
      end

      attr_reader :events

      def status_variant(status)
        case status
        when "processed" then :success
        when "failed"    then :danger
        when "received"  then :warning
        else                  :default
        end
      end

      # Only received/failed events are stranded and worth redriving; a processed
      # event's redrive would no-op in the job anyway.
      def redrivable?(event)
        event.status.in?(%w[received failed])
      end

      def status_label(status)
        key = status.to_s
        if Payments::WebhookEvent::STATUSES.include?(key)
          I18n.t("comp_payments.webhook_events.statuses.#{key}")
        else
          key
        end
      end

      def provider_label(provider)
        Payments::Gateways.for(provider).display_name
      rescue ArgumentError
        provider.to_s
      end
    end
  end
end
