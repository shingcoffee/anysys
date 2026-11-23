# frozen_string_literal: true

module Admin
  module Modules
    module Emails
      class SendActivityCancellationsController < ApplicationController
        dashboard_menu_item :modules
        before_action :require_email_module!
        before_action :load_send_activity

        def create
          show_path = "/#{current_customer.id}/admin/modules/emails/send_activities/#{@send_activity.id}"
          if @send_activity.cancel!
            redirect_to show_path, notice: t("admin_modules.flash.send_activities.cancelled")
          else
            redirect_to show_path, alert: t("admin_modules.flash.send_activities.not_cancellable",
                                            status: @send_activity.status_label)
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
