# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        class FlowchartCatalog < Section
          heads "This workspace's flowcharts"

          private

          def body
            return nil unless context.flowchart_visible?

            catalog = context.flowchart_catalog
            return "This workspace has no flowcharts yet. Anything you define is a create." if catalog.empty?

            <<~TEXT
              Live customer-owned flowcharts in this tenant (name, status, description).
              A name that matches one of these is an update of that flowchart.

              ```json
              #{json(catalog)}
              ```
            TEXT
          end
        end
      end
    end
  end
end
