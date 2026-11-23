# frozen_string_literal: true

module Admin
module Maintenance
module Platform
module CodeGenerators
  # IoParamsController
  #
  # Platform-owner-only JSON endpoint for inspecting a
  # step action's config. Given an action name and its in-progress config hash,
  # returns the input and output ctx pins that the generator would expose.
  #
  # Endpoint: POST /:cid/admin/maintenance/platform/code_generators/:action_name/io_params
  #
  # Request body (JSON):
  #   { "config": { "httpMethod": "GET", "url": "\"https://example.com\"", ... } }
  #
  # Response (always 200):
  #   {
  #     "inputs":  [{ "pin": "api_url", "ctx_key": "api_url", "source": "config_expr" }],
  #     "outputs": [{ "pin": "resp",    "ctx_key": "resp" }]
  #   }
  #
  # Unknown actions or extraction errors yield `{ "inputs": [], "outputs": [] }`
  # with HTTP 200 so the UI stays responsive during half-typed edits — the
  # endpoint never returns 4xx/5xx for mid-edit smoothness.
  class IoParamsController < ApplicationController
    include GeneratorIoIntrospection
    dashboard_menu_item :maintenance

    # Mounted under /:cid/admin/maintenance/platform/... so RouteAuthorization
    # gates the request to platform-owner users. Tenant editors use the separate
    # flowcharts endpoints; authorization and CSRF checks remain in force here.
    def show
      render_generator_io(:config) do |config|
        ::CodeGenerators::IoExtractor.call(action: params[:generator_action].to_s, config: config)
      end
    end
  end
end
end
end
end
