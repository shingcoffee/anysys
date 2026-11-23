# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module End
      class EndGenerator < BaseGenerator
        generator_metadata do
          description "Finishes the run successfully; reaching an End never refuses the submission. With " \
                      "responseType value it first writes returnValue to ctx[:response], which is how a flowchart " \
                      "run as a subflow hands a result back to its parent. Without a response it compiles to the " \
                      "Railway's End.success and adds no step."
          category :flow_control
          version "1.1.0"
        end

        config_schema do
          enum :responseType, %w[none value], default: "none", required: true,
                              description: "none ends with no result. value writes returnValue to ctx[:response] " \
                                           "for the parent flowchart that runs this one as a subflow."
          expression :returnValue, placeholder: true, example: "ctx[:result]", visible: { responseType: "value" },
                                   description: "Result written to ctx[:response]: a ctx path such as " \
                                                "ctx.order.total or any Ruby expression such as ctx[:total] * 2. " \
                                                "Quote text: \"approved\"."
          requires :returnValue, when: { responseType: "value" }
        end

        def generate_body
          case value("responseType").to_s
          when "value"
            <<~RUBY.chomp
              ctx[:response] = #{return_expr}
              true
            RUBY
          else
            "true"
          end
        end

        private

        # A dotted ctx path reads through Step.dig; anything else is the
        # expression the role declares.
        def return_expr
          raw = value(:returnValue).to_s.strip
          raw.start_with?("ctx.") ? safe_read(raw.delete_prefix("ctx.")) : read(:returnValue)
        end
      end
    end
  end
end
