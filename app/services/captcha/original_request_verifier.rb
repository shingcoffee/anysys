# frozen_string_literal: true

module Captcha
  # Rails' CSRF verifier in the ORIGINAL route/controller context, without
  # executing its action/callbacks. A challenge's per-form token does not prove
  # that a token for the original POST was valid.
  class OriginalRequestVerifier
    def self.verify!(request)
      # Populate the original env's parser cache before cloning it. Otherwise
      # token verification could consume the shared rack.input stream while the
      # snapshot/replay dispatch still believes the body has not been parsed.
      request.request_parameters
      context = ActionDispatch::Request.new(request.env.dup)
      context.delete_header("action_dispatch.request.path_parameters")
      context.delete_header("action_dispatch.request.parameters")
      Rails.application.routes.recognize_path_with_request(context, context.path_info, {})
      controller = context.controller_class.new
      controller.set_request!(context)
      controller.set_response!(ActionDispatch::Response.new)
      return if controller.send(:verified_request?)

      raise ActionController::InvalidAuthenticityToken
    end
  end
end
