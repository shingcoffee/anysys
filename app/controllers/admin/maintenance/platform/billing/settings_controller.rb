# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Billing
        # Platform-owner management of global billing settings (Area d).
        #
        # The settings row is a global singleton accessed via Billing::Settings.current.
        # No customer_id is involved. show/edit/update follow the standard singular
        # resource pattern.
        class SettingsController < BaseController
          before_action :set_settings

          def show
          end

          def edit
            @form = @contract = ::Billing::Contracts::Settings.new(@settings)
          end

          def update
            attrs = settings_params.to_h
            if attrs.key?("dunning_schedule")
              @submitted_dunning_schedule = attrs["dunning_schedule"]
              attrs["dunning_schedule"] = parsed_dunning_schedule(@submitted_dunning_schedule)
            end
            result = ::Billing::Activities::UpdateSettings.call(settings: @settings, params: attrs)
            if result.status == :saved
              redirect_to admin_maintenance_platform_billing_settings_path(current_customer_id),
                          status: :see_other,
                          notice: t("maint_platform.flash.billing.settings_updated")
            else
              render_billing_failure(result, :edit)
            end
          end

          private

          def set_settings
            @settings = ::Billing::Settings.current
          end

          def settings_params
            params.require(:billing_settings).permit(
              :tax_rate_bps, :collection_mode,
              :grace_period_days, :trial_ending_notice_days, :dunning_schedule
            )
          end

          # The settings form submits dunning_schedule as a comma-separated string
          # (e.g. "1, 3, 7"). Parse it into an integer array before persisting.
          def parsed_dunning_schedule(raw)
            return raw unless raw.is_a?(String)
            return [] if raw.strip.empty?
            raw.split(",", -1).map(&:strip).map do |token|
              token.match?(/\A[1-9]\d*\z/) ? Integer(token, 10) : token
            end
          end
        end
      end
    end
  end
end
