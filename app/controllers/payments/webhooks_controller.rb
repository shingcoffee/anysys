# frozen_string_literal: true

module Payments
  class WebhooksController < ActionController::API
    # PSP webhooks: no CSRF, no session/auth. ActionController::API skips all that.

    def create
      body = request.raw_post
      Payments::WebhookDispatcher.call(provider: params[:provider],
                                       headers: request.headers.to_h,
                                       body: body)
      # Alipay's notify protocol acks with the literal body "success"; anything
      # else (including an empty 200) is treated as failure and redelivered for
      # ~24h. Other PSPs key off the 2xx status alone.
      params[:provider] == "alipay" ? render(plain: "success") : head(:ok)
    rescue Payments::Errors::SignatureInvalid
      head :bad_request
    rescue Payments::Errors::TenantNotFound
      head :not_found
    rescue Payments::Errors::Error => e
      Rails.logger.error("[payments.webhook] #{e.class}: #{e.message}")
      head :internal_server_error
    end
  end
end
