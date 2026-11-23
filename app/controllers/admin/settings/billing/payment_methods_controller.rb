# frozen_string_literal: true

require "uri"

module Admin
  module Settings
    module Billing
      class PaymentMethodsController < BaseController
        ALIPAY_ACTION_HOSTS = %w[openapi.alipay.com openapi.alipaydev.com openapi-sandbox.dl.alipaydev.com].freeze

        before_action :set_payment_method, only: %i[destroy make_default authorization confirmation]
        before_action :private_authorization_response, only: %i[index create setup_intent authorization confirmation]

        def index
          if valid_billing_request_key?(params[:authorization_request_key])
            method = ::Billing::PaymentMethod.for_current_customer.find_by!(request_key: params[:authorization_request_key])
            return redirect_to authorization_admin_settings_billing_payment_method_path(current_customer_id, method),
                               status: :see_other
          end
          assign_index
        end

        def create
          prepare_method(payment_method_params[:provider])
        end

        def setup_intent
          prepare_method("stripe")
        end

        # The provider return is display-only. Query-string token/intent hints
        # cannot activate the method, and this GET never reconciles at the PSP.
        def authorization
          @authorization_action = controlled_action(::Billing::PaymentAuthorization.action_for(
            payment_method: @payment_method,
            return_url: authorization_admin_settings_billing_payment_method_url(current_customer_id, @payment_method)
          ))
          assign_authorization
          respond_to do |format|
            format.html { render :authorization }
            format.json { render json: method_payload(@payment_method.status, @authorization_action) }
          end
        end

        def confirmation
          # B queries the exact persisted authorization_reference/account and
          # passes provider-verified evidence to confirm!. Browser hints are ignored.
          result = ::Billing::PaymentAuthorization.confirm!(payment_method: @payment_method)
          respond_method_result(result)
        end

        def destroy
          result = ::Billing::Activities::RemovePaymentMethod.call(payment_method: @payment_method)
          return render_method_failure(result) unless %i[removed unchanged pending].include?(result.status)
          key = result.payment_method&.revocation_state == "pending" || result.status == :pending ? "revocation_pending" : "removed"
          redirect_to admin_settings_billing_payment_methods_path(current_customer_id), status: :see_other,
                      notice: t("admin_settings.flash.payment_methods.#{key}")
        end

        def make_default
          result = ::Billing::Activities::MakeDefaultPaymentMethod.call(customer: current_customer, payment_method: @payment_method)
          return render_method_failure(result) unless %i[updated saved active unchanged].include?(result.status)
          redirect_to admin_settings_billing_payment_methods_path(current_customer_id), status: :see_other,
                      notice: t("admin_settings.flash.payment_methods.default_updated")
        end

        private

        def assign_index
          assign_billing_methods
          @payment_methods = paginate_billing(@payment_methods)
          @payment_method_readiness = @payment_methods.to_h do |method|
            [method.id, billing_method_readiness(method, currency: @currency, provider_options: @provider_options)]
          end
          unless instance_variable_defined?(:@request_key)
            @request_key = params.permit(:request_key)[:request_key] || SecureRandom.uuid
          end
          @form ||= ::Billing::Contracts::PaymentMethod.new(OpenStruct.new(provider: nil, request_key: @request_key))
          @contract = @form
        end

        def prepare_method(provider)
          @request_key = payment_method_params[:request_key]
          @form = ::Billing::Contracts::PaymentMethod.new(OpenStruct.new(provider: provider, request_key: @request_key))
          unless valid_billing_request_key?(@request_key)
            @form.errors.add(:request_key, t("admin_settings.errors.validations.billing_request_key"))
            return render_method_failure(::Billing::Result.new(status: :invalid, reason: :billing_request_key, form: @form))
          end
          result = ::Billing::Activities::SetUpPaymentMethod.call(
            customer: current_customer, actor: current_user, provider: provider, request_key: @request_key,
            return_url: admin_settings_billing_payment_methods_url(current_customer_id)
          )
          respond_method_result(result)
        end

        def respond_method_result(result)
          assign_billing_result(result)
          return render_method_failure(result) unless %i[active authorization_required pending unchanged].include?(result.status)
          @payment_method = result.payment_method || @payment_method
          assign_authorization
          @authorization_action = controlled_action(result.action)
          if result.action && !@authorization_action
            return render_method_failure(::Billing::Result.new(status: :invalid, reason: :authorization_action_invalid))
          end
          respond_to do |format|
            format.json do
              render json: method_payload(result.status, @authorization_action),
                     status: result.status == :pending ? :accepted : :ok
            end
            format.html do
              if @authorization_action && @authorization_action[:kind] == :redirect
                redirect_to @authorization_action.fetch(:url), allow_other_host: true, status: :see_other
              elsif @authorization_action
                render :authorization, status: :ok
              else
                key = result.status == :active ? "authorized" : "pending_authorization"
                redirect_to admin_settings_billing_payment_methods_path(current_customer_id), status: :see_other,
                            notice: t("admin_settings.flash.payment_methods.#{key}")
              end
            end
          end
        end

        def method_payload(status, action)
          payload = { payment_method_id: @payment_method.id, status: status,
                      confirmation_url: @confirmation_url,
                      action: action }
          payload[:client_secret] = action[:client_secret] if action && action[:kind] == :stripe_setup
          payload
        end

        def assign_authorization
          @subscription = live_subscription
          @currency = billing_currency
          assign_provider_options
          @provider_options = @provider_options.select { |option| option.fetch(:key) == @payment_method.provider }
          @available_providers = @provider_options.select { |option| option.fetch(:enabled) }.map { |option| option.fetch(:key) }
          @confirmation_url = confirmation_admin_settings_billing_payment_method_url(current_customer_id, @payment_method)
          @request_key = @payment_method.request_key
        end

        # Only B's typed action is presented; never forward a raw provider result
        # or a browser-supplied destination/field map into HTML or JSON.
        def controlled_action(action)
          return unless action.is_a?(Hash)
          case action[:kind]&.to_sym
          when :stripe_setup
            return unless @payment_method.provider == "stripe" && action[:publishable_key].present? && action[:client_secret].present?
            action.slice(:publishable_key, :client_secret).merge(kind: :stripe_setup)
          when :redirect
            return unless @payment_method.provider == "alipay" && alipay_destination?(action[:url])
            { kind: :redirect, url: action[:url] }
          when :provider_form
            return unless @payment_method.provider == "alipay" && alipay_destination?(action[:action_url]) &&
                          action[:method].to_s.downcase == "post" && action[:fields].is_a?(Hash) &&
                          action[:fields].all? { |key, value| key.is_a?(String) && value.is_a?(String) }
            { kind: :provider_form, action_url: action[:action_url], method: "post", fields: action[:fields] }
          end
        end

        def alipay_destination?(value)
          return false unless value.is_a?(String)
          uri = URI.parse(value)
          uri.scheme == "https" && ALIPAY_ACTION_HOSTS.include?(uri.host) && uri.port == 443 &&
            uri.userinfo.nil? && uri.fragment.nil? && uri.path == "/gateway.do"
        rescue URI::InvalidURIError
          false
        end

        def render_method_failure(result)
          assign_billing_result(result)
          respond_to do |format|
            format.html do
              assign_index
              flash.now[:alert] = billing_failure_message(result)
              render :index, status: billing_failure_status(result)
            end
            format.json do
              render json: { status: result.status, reason: result.reason, error: billing_failure_message(result) },
                     status: billing_failure_status(result)
            end
          end
        end

        def private_authorization_response
          response.headers["Cache-Control"] = "no-store, private"
          response.headers["Referrer-Policy"] = "no-referrer"
        end

        def set_payment_method
          @payment_method = ::Billing::PaymentMethod.for_current_customer.find(params[:id])
        end

        def payment_method_params
          params.require(:billing_payment_method).permit(:provider, :request_key)
        end
      end
    end
  end
end
