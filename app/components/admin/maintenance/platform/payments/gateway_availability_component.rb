# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Payments
        # Providers surface for the Payment module: one row per registered
        # gateway with the platform-wide availability toggle that decides
        # whether tenants may enable it at all.
        class GatewayAvailabilityComponent < ApplicationComponent
          FLOW_KEYS = %w[qr h5 jsapi card].freeze

          def initialize(gateways:, customer_id:)
            @gateways = Array(gateways)
            @customer_id = customer_id
          end

          attr_reader :gateways, :customer_id

          def available_count
            gateways.count { |_gateway, platform_gateway| platform_gateway.available? }
          end

          def summary
            I18n.t("maint_platform.module_settings.show.payment.available_count",
              count: available_count, total: gateways.size)
          end

          def toggle_path(provider_key)
            helpers.admin_maintenance_platform_module_settings_payment_gateway_path(customer_id, provider_key)
          end

          def flows(gateway)
            Array(gateway.supported_flows).map { |flow|
              key = flow.to_s
              if FLOW_KEYS.include?(key)
                I18n.t("maint_platform.module_settings.show.payment.flows.#{key}")
              else
                key
              end
            }
          end
        end
      end
    end
  end
end
