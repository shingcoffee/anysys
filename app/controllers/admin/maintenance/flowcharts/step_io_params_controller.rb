# frozen_string_literal: true

module Admin
  module Maintenance
    module Flowcharts
      class StepIoParamsController < ApplicationController
        include GeneratorIoIntrospection
        dashboard_menu_item :maintenance

        # RouteAuthorization requires admin/owner; TenantContext rejects other
        # tenants for admins. POST carries config only: emitted Ruby is analyzed,
        # never executed, and no flowchart is read or written.
        def show
          render_generator_io(:config) do |config|
            ::CodeGenerators::IoExtractor.call(action: params[:generator_action].to_s, config: config)
          end
        end
      end
    end
  end
end
