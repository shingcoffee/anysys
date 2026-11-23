# frozen_string_literal: true

module Admin
  module Modules
    module Emails
      class SendActivityDeliveriesController < ApplicationController
        dashboard_menu_item :modules
        before_action :require_email_module!
        before_action :load_send_activity

        def create
          path = "/#{current_customer.id}/admin/modules/emails/send_activities/#{@send_activity.id}"
          # Shared atomic-claim path — also schedules the next recurring
          # occurrence, which a direct start! would have skipped.
          if ::Emails::SendActivities::StartSendActivity.call(@send_activity)
            redirect_to path, notice: t("admin_modules.flash.send_activities.sending")
          else
            alert = @send_activity.errors.full_messages.to_sentence.presence ||
              t("admin_modules.flash.send_activities.not_startable", status: @send_activity.reload.status_label)
            redirect_to path, alert: alert
          end
        end

        private

        def require_email_module!
          return if FeatureModules::Module.enabled?(key: "email", customer_id: current_customer.id)

          head :not_found
        end

        def load_send_activity
          @send_activity = ::Emails::SendActivities::SendActivity.for_current_customer.find(params[:send_activity_id])
        end
      end
    end
  end
end
