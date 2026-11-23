# frozen_string_literal: true

module Admin
module Maintenance
module Platform
module CodeGenerators
  # ElementTypeIoParamsController
  #
  # Platform-owner-only JSON endpoint for inspecting
  # an element's properties. Given an element_type and its in-progress
  # properties hash, returns the ctx input and output pins that the
  # element-type generator would expose.
  #
  # Endpoint: POST /:cid/admin/maintenance/platform/code_generators/element_types/:element_type/io_params
  #
  # Request body (JSON):
  #   { "properties": { "loopType": "for_each", "collection": "ctx[:items]" } }
  #
  # Response (always 200):
  #   {
  #     "inputs":  [{ "pin": "items", "ctx_key": "items", "source": "config_expr" }],
  #     "outputs": [{ "pin": "item",  "ctx_key": "item" }, ...]
  #   }
  #
  # Unknown element_type or extraction errors yield `{"inputs": [], "outputs": []}`
  # with HTTP 200 so the UI stays responsive during half-typed edits.
  class ElementTypeIoParamsController < ApplicationController
    include GeneratorIoIntrospection
    dashboard_menu_item :maintenance

    # Mounted under /:cid/admin/maintenance/platform/... so RouteAuthorization
    # gates the request to platform-owner users. Tenant editors use the separate
    # flowcharts endpoints; authorization and CSRF checks remain in force here.
    def show
      render_generator_io(:properties) do |properties|
        ::CodeGenerators::IoExtractor.call_element(element_type: params[:element_type].to_s, properties: properties)
      end
    end
  end
end
end
end
end
