# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module CodeGenerators
        class TestRunsController < ApplicationController
          dashboard_menu_item :maintenance

          def create
            relative = params[:code_generator_slug].to_s
            return head :bad_request if relative.include?("..")

            registry_entry = ::CodeGenerators::PathIdentity.find(relative)
            unless registry_entry
              return render json: { error: t("maint_platform.flash.code_generators.generator_not_found") }, status: :not_found
            end

            sample_config = parse_config
            return if performed?

            result = ::CodeGenerators::TestRunner.run(registry_entry, config: sample_config)
            render json: {
              body:              result[:body],
              code:              result[:code],
              inputs:            result[:inputs],
              outputs:           result[:outputs],
              validation_errors: result[:validation_errors].map(&:to_s),
              html:              result_html(result: result)
            }, status: result[:validation_errors].any? ? :unprocessable_entity : :ok
          end

          private

          def parse_config
            raw = params[:sample_config].presence || "{}"
            raw.is_a?(String) ? JSON.parse(raw) : raw
          rescue JSON::ParserError => e
            error = t("maint_platform.flash.code_generators.invalid_json", error: e.message)
            render json: { error: error, html: result_html(error: error) }, status: :unprocessable_entity
          end

          def result_html(**)
            view_context.render(::Platform::CodeGenerators::PlaygroundResultComponent.new(**))
          end
        end
      end
    end
  end
end
