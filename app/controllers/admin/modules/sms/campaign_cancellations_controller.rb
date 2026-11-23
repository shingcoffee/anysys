# frozen_string_literal: true

module Admin
  module Modules
    module Sms
      class CampaignCancellationsController < CampaignsController
        before_action :load_campaign, only: :create

        def create
          action_attributes
          result = ::Sms::Campaigns::Cancel.call(customer: current_customer, actor: current_user, campaign: @campaign)
          if result.success?
            @campaign = result.value
            success_response(public_record(@campaign), location: admin_modules_sms_campaign_path(current_customer_id, @campaign), notice: :cancelled)
          else
            @errors = result.errors
            prepare_show
            render_failure(result, template: "admin/modules/sms/campaigns/show")
          end
        end
      end
    end
  end
end
