# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Payments
        # Platform-owner cross-tenant ledger of inbound PSP webhook events (the
        # idempotency log behind WebhookDispatcher + ProcessWebhookEventJob), with
        # a per-event redrive. Owner-only via RouteAuthorization (platform area).
        #
        # Deliberately global rather than tenant-scoped: a webhook is recorded at
        # dispatch time BEFORE its tenant is resolved, so customer_id is nil for
        # exactly the received/failed events an operator needs to see and redrive.
        class WebhookEventsController < ApplicationController
          dashboard_menu_item :maintenance

          def index
            @events = ::Payments::WebhookEvent.order(created_at: :desc).limit(100)
          end

          # Re-enqueue processing of a single stranded event, mirroring the cron
          # reaper's redrive (flip back to "received", re-dispatch the job).
          # Only received/failed events are eligible — processed events stay
          # settled so a crafted POST cannot replay a completed webhook.
          def redrive
            event = ::Payments::WebhookEvent.find(params[:id])
            claimed = false
            event.with_lock do
              unless event.status.in?(%w[received failed]) && !event.processing?
                next
              end

              event.update!(status: "received")
              ::Payments::ProcessWebhookEventJob.perform_later(event.id, event.signing_merchant_id, event.signing_account_id)
              claimed = true
            end
            unless claimed
              redirect_to admin_maintenance_platform_module_settings_payment_webhook_events_path(current_customer_id),
                          alert: t("comp_payments.flash.webhook_redrive_not_retryable")
              return
            end

            redirect_to admin_maintenance_platform_module_settings_payment_webhook_events_path(current_customer_id),
                        notice: t("comp_payments.flash.webhook_redriven")
          end
        end
      end
    end
  end
end
