# frozen_string_literal: true

module FeatureModules
  # The framework hop between a page submission and a module's entry_path
  # (public URL /:customer_id/handoff). Every page → module handoff lands here,
  # whatever the module:
  #
  # 1. Leaves Turbo Drive. A page form submits through Turbo, which would
  #    otherwise fetch the module's pages in the background (wrong format,
  #    blocked cross-origin redirects). The layout's turbo-visit-control meta
  #    makes Turbo reload this URL as a top-level navigation instead.
  # 2. Collects the module's user_fillable inputs on a generic entry step,
  #    pre-filled from the invocation (FeatureModules::HandoffCompletion is the
  #    security boundary: author_only inputs can never be overwritten).
  # 3. Redirects to the module's entry_path, which reads the invocation via
  #    InvocationContext#require_module_invocation.
  class HandoffsController < ApplicationController
    include FeatureModules::InvocationContext
    include ComponentPageRendering

    layout "feature_module_handoff"

    before_action :load_invocation

    def show
      return render_continue if turbo_request?
      return render_entry if @invocation[:awaiting_input]

      redirect_to_entry
    end

    def update
      return redirect_to_entry unless @invocation[:awaiting_input]

      result = FeatureModules::HandoffCompletion.complete!(
        session:      session,
        invocation:   @invocation,
        user_params:  entry_params,
        registration: registration
      )
      return redirect_to_entry if result.ok?

      render_entry(values: entry_params, errors: result.errors, status: :unprocessable_content)
    end

    private

    def load_invocation
      @invocation = current_invocation
      return if @invocation && feature_module

      redirect_to root_path, alert: t("feature_modules.handoff.no_active_request")
    rescue FeatureModules::CrossTenantViolation
      head :forbidden
    end

    def feature_module
      @feature_module ||= FeatureModules::Module.find_by(key: @invocation[:module_key])
    end

    def registration
      feature_module.registration_class
    end

    def entry_path
      registration.entry_path_for(current_customer)
    end

    def redirect_to_entry
      path = entry_path
      return redirect_to(root_path, alert: t("feature_modules.handoff.no_active_request")) if path.blank?

      redirect_to path
    end

    # See Payments::CheckoutsController#allow_browser — in-app browsers that
    # are not :modern still need to complete a page → module hop.
    def allow_browser(versions:, block:)
    end

    # Turbo fetch requests carry X-Turbo-Request-Id, including the redirected
    # GET that follows a Turbo form submission.
    def turbo_request?
      request.headers["X-Turbo-Request-Id"].present?
    end

    # Turbo discards this body and reloads the URL top-level (layout meta).
    def render_continue
      render html: "", layout: true
    end

    def render_entry(values: @invocation[:input], errors: nil, status: :ok)
      render FeatureModules::HandoffEntryComponent.new(
        fields:       FeatureModules::HandoffCompletion.user_fillable_fields(registration),
        values:       values,
        errors:       errors,
        i18n_scope:   registration.handoff_entry_i18n_scope,
        submit_url:   feature_module_handoff_path(current_customer_id)
      ), status: status
    end

    # A first guard on top of HandoffCompletion's own fillable-only filter.
    def entry_params
      names   = FeatureModules::HandoffCompletion.user_fillable_fields(registration).map(&:name)
      handoff = params[:handoff]
      return {} unless handoff.is_a?(ActionController::Parameters)

      handoff.permit(*names).to_h
    end
  end
end
