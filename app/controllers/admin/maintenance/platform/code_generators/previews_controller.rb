# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module CodeGenerators
        class PreviewsController < ApplicationController
          dashboard_menu_item :maintenance

          def show
            relative = params[:code_generator_slug].to_s
            return head :bad_request if relative.include?("..")

            registry_entry = ::CodeGenerators::PathIdentity.find(relative)

            if registry_entry
              sample = registry_entry.sample_input
              element = { "config" => sample, "properties" => sample, "label" => "preview_step" }
              generator = registry_entry.new(element, {})
              render json: { preview_code: generator.generate_step_method }
            else
              render json: { preview_code: nil }
            end
          end
        end
      end
    end
  end
end
