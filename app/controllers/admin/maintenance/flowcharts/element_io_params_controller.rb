# frozen_string_literal: true

module Admin
  module Maintenance
    module Flowcharts
      class ElementIoParamsController < ApplicationController
        include GeneratorIoIntrospection
        dashboard_menu_item :maintenance

        # Uses the central admin/owner and tenant guards. Subflow emission is
        # nil: introspection does not resolve or expose referenced flowcharts.
        def show
          render_generator_io(:properties) do |properties|
            ::CodeGenerators::IoExtractor.call_element(element_type: params[:element_type].to_s, properties: properties)
          end
        end
      end
    end
  end
end
