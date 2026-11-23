# frozen_string_literal: true

module Admin
  module Modules
    module Sms
      # Tenant-scoped FeatureModules::Module handoff endpoint. Flowchart steps / host
      # services that can't reach the Ruby gateway directly POST here.
      # The controller runs the exact same activity as ::Sms::Gateway.send —
      # it's just a thin HTTP surface on top.
      class SendsController < ApplicationController
        dashboard_menu_item :modules

        # RouteAuthorization and TenantContext supply the inherited role gate
        # and URL-derived customer. The core checks module enablement AFTER
        # genuine idempotency replay, so disabling SMS does not hide its ledger.
        def create
          input = validated_input
          message = ::Sms::Gateway.send(customer: current_customer, **input)
          render json: payload_for(message), status: message.status == "queued" ? :accepted : :ok
        rescue ::Sms::Errors::ModuleDisabled
          head :not_found
        rescue ::Sms::Errors::IdempotencyConflict
          render json: { error: "idempotency_conflict", message: t("sms_integration.errors.idempotency_conflict") },
                 status: :conflict
        rescue ::Sms::Errors::TemplateVarsInvalid => e
          render json: { error: "invalid_request", message: e.message }, status: :unprocessable_content
        rescue ::Sms::Errors::RateLimited => e
          render json: { error: "rate_limited", window: e.window }, status: :too_many_requests
        rescue ::Sms::Errors::DailyCapExceeded
          render json: { error: "daily_cap_exceeded", message: t("admin_modules.sms.errors.daily_cap_exceeded") },
                 status: :too_many_requests
        rescue ::Sms::Errors::CredentialsMissing
          render json: { error: "credentials_missing", message: t("admin_modules.sms.errors.credentials_missing") },
                 status: :service_unavailable
        rescue ::Sms::Errors::TransportError
          render json: { error: "transport_error", message: t("admin_modules.sms.errors.transport_error") },
                 status: :bad_gateway
        end

        private

        def validated_input
          input = { to: params[:to], template_key: params[:template_key], vars: normalized_vars,
                    idempotency_key: params[:idempotency_key] }
          errors = ::Sms::SendStandards.validation_errors(**input)
          if errors.any?
            messages = errors.map { |field, message| t("sms_integration.errors.invalid_field", field: field, message: message) }
            raise ::Sms::Errors::TemplateVarsInvalid, messages.to_sentence
          end

          key = params[:idempotency_key]
          if key&.match?(/[[:cntrl:]]/)
            raise ::Sms::Errors::TemplateVarsInvalid,
                  t("sms_integration.errors.idempotency_key_invalid", limit: ::Sms::SendStandards::MAX_KEY_BYTES)
          end

          # HTTP clients cannot supply an unparsed/unchecked deadline. Trusted
          # Ruby callers use Gateway.send(expires_at:) with the core validation.
          if params.key?(:expires_at)
            raise ::Sms::Errors::TemplateVarsInvalid, t("sms_integration.errors.expiry_not_supported")
          end

          # Validate bytes/encoding/control characters before treating a blank
          # string as absent, matching the core admission's lifecycle contract.
          input.merge(idempotency_key: key.presence)
        end

        def normalized_vars
          raw = params[:vars]
          return {} if raw.nil?

          # Only unwrap Rails' object proxy; malformed strings/arrays/scalars
          # stay intact for the shared SQL-free standards gate to reject.
          raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw
        end

        def payload_for(message)
          {
            message_id: message.id,
            status: message.status,
            vendor_message_id: message.vendor_message_id,
            failure_code: message.failure_code,
            failure_message: message.displayed_failure_message,
            expires_at: message.expires_at&.iso8601
          }
        end
      end
    end
  end
end
