# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module CodeGenerators
        class ValidationsController < ApplicationController
          dashboard_menu_item :maintenance

          def create
            source = edited_source
            return head(:not_found) unless source

            errors = ::CodeGenerators::GeneratorValidator.validate_source(source)
            render json: { valid: errors.empty?, errors: errors }
          end

          private

          # Only registered generator paths resolve, so the slug cannot name
          # any other file.
          def edited_source
            relative = params[:code_generator_slug].to_s
            return unless ::CodeGenerators::PathIdentity.find(relative)

            path = Rails.root.join("app/services/code_generators", "#{relative}.rb")
            return unless File.file?(path)

            ::CodeGenerators::SourceDocument.new(File.read(path)).with_body(params[:methods_body].to_s)
          end
        end
      end
    end
  end
end
