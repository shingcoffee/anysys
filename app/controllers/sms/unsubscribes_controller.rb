# frozen_string_literal: true

module Sms
  class UnsubscribesController < ApplicationController
    layout "public_page"

    skip_before_action :authenticate_user!, only: %i[show create], raise: false
    skip_before_action :enforce_mfa!, only: %i[show create], raise: false
    # These public browser forms retain Rails CSRF verification. The service
    # validates the signed tenant/contact/phone; unsigned URL tenant hints are
    # never used to establish Current or passed to it.

    def show
      display_preview
    end

    def create
      result = Campaigns::Unsubscribe.call(token: request.path_parameters[:token])
      if result.success?
        display_preview
      else
        display_invalid(result)
      end
    end

    private

    def display_preview
      result = Campaigns::Unsubscribe.preview(token: request.path_parameters[:token])
      return display_invalid(result) unless result.success?

      @unsubscribe = result.value.slice(:masked_phone, :already_unsubscribed)
      @errors = {}
      respond_to do |format|
        format.html { render :show }
        format.json { render json: { data: @unsubscribe } }
      end
    end

    def display_invalid(result)
      @unsubscribe = nil
      @errors = result.errors.presence || { base: [t("sms_campaign_http.errors.invalid_unsubscribe")] }
      respond_to do |format|
        format.html { render :show, status: :not_found }
        format.json { render json: { error: { code: :not_found, errors: @errors } }, status: :not_found }
      end
    end
  end
end
