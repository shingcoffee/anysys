# frozen_string_literal: true

module Emails
  class TrackingController < ActionController::Base
    # No CSRF since these are public endpoints accessed via email clients.
    skip_forgery_protection if respond_to?(:skip_forgery_protection)

    before_action :find_message
    before_action :verify_signature!

    # 1x1 transparent GIF (Base64)
    PIXEL = Base64.decode64("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")

    def open
      Emails::MessageEvent.record_open!(@message, request: request)

      send_data PIXEL, type: "image/gif", disposition: "inline"
    end

    def click
      url = params[:url].to_s
      return head(:bad_request) unless safe_redirect_url?(url)

      Emails::MessageEvent.record_click!(@message, url: url, request: request)

      redirect_to url, allow_other_host: true, status: :found
    end

    private

    def find_message
      @message = Emails::Message.find_by(id: params[:message_id])
    end

    def verify_signature!
      # Missing message and bad/missing signature share 404 so sequential IDs
      # are not an unauthenticated existence oracle (404 vs 401).
      return head(:not_found) unless @message && signature_matches?
    end

    def signature_matches?
      sig = params[:sig].to_s
      return false if sig.blank?

      payload = Rails.application.message_verifier(:email_tracking).verify(sig)

      if action_name == "click"
        payload = payload.with_indifferent_access if payload.is_a?(Hash)
        payload.is_a?(Hash) && payload[:message_id].to_s == @message.id.to_s && payload[:url] == params[:url]
      else
        payload.to_s == @message.id.to_s
      end
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      false
    end

    def safe_redirect_url?(url)
      uri = URI.parse(url)
      return false unless uri.is_a?(URI::HTTP)
      return false if uri.userinfo.present?
      return false if uri.host.blank?

      true
    rescue URI::InvalidURIError
      false
    end
  end
end
