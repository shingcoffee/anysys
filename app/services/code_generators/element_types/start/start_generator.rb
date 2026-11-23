# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Start
      class StartGenerator < BaseGenerator
        generator_metadata do
          description "Manual entry point of the flowchart. Skipped in DFS traversal."
          category :flow_control
          version "1.0.0"
        end

        config_schema do
        end

        def generate_body
          nil
        end
      end
    end
  end
end
