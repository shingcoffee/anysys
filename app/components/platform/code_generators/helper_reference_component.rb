# frozen_string_literal: true

module Platform
  module CodeGenerators
    class HelperReferenceComponent < ApplicationComponent
      HELPERS = {
        config_schema: "config_schema do … end",
        read: "read(:field)",
        value: "value(:field)",
        assign: "assign(:output, source)",
        literal: "literal(value)",
        fail_with: "fail_with(:code, field:, unless:)",
        attempt: "attempt(:code, ErrorClass) { lines }",
        body: "body(*lines)"
      }.freeze

      private

      def roles
        ::CodeGenerators::ConfigSchema::ROLES
      end
    end
  end
end
