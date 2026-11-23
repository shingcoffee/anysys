# frozen_string_literal: true

module Admin
  module Modules
    module Sms
      class CampaignLaunchesController < CampaignsController
        before_action :load_campaign, only: :create

        def create
          raw = action_attributes(:lock_version, :review_token)
          version = ::Sms::RequestAttributes.integer(raw[:lock_version], field: :lock_version)
          token = raw[:review_token]
          unless token.is_a?(String) && token.present? && token.valid_encoding? && token.bytesize <= 16 * 1024
            raise ::Sms::RequestAttributes::Invalid.new(:review_token, :invalid_review, code: :review_changed)
          end
          result = ::Sms::Campaigns::Launch.call(customer: current_customer, actor: current_user, campaign: @campaign,
                                                lock_version: version, review_token: token)
          if result.success?
            @campaign = result.value
            success_response(public_record(@campaign), location: admin_modules_sms_campaign_path(current_customer_id, @campaign), status: :accepted, notice: :launched)
          else
            @errors = result.errors
            @campaign.reload
            prepare_show
            render_failure(result, template: "admin/modules/sms/campaigns/show")
          end
        end
      end
    end
  end
end
