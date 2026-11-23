# frozen_string_literal: true

module CodeGenerators
  class TestRunner
    class << self
      # Compile a generator against config (and optional flowchart topology context).
      # Returns body/code/IO/validation_errors without executing the step.
      def run(generator_class, config: {}, context: {})
        unless config.is_a?(Hash)
          return invalid_result([I18n.t("maint_platform.flash.code_generators.config_object_required")])
        end

        element = {
          "config" => config,
          "properties" => config,
          "label" => "test_step"
        }

        generator = generator_class.new(element, context || {})
        validation_errors = generator.validate_config(config)
        return invalid_result(validation_errors) if validation_errors.any?

        body = generator.generate_body
        code = generator.generate_step_method
        io = CodeIntrospector.analyze(body)

        {
          body: body,
          code: code,
          inputs: io[:inputs],
          outputs: io[:outputs],
          validation_errors: validation_errors
        }
      end

      # Compile + invoke the generated step method against +ctx+.
      # Stubs belong in the caller (facade doubles), not here.
      #
      # @return [Hash] run() keys plus :outcome (step return) and :ctx
      def execute(generator_class, config: {}, context: {}, ctx: {})
        result = run(generator_class, config: config, context: context)
        return result if result[:validation_errors].any?
        code = result[:code]
        raise ArgumentError, "#{generator_class.name} produced no step method" if code.nil?

        host = Class.new
        host.class_eval(code) # rubocop:disable Security/Eval -- controlled generated step under test
        method_name = host.instance_methods(false).first
        raise ArgumentError, "#{generator_class.name} step method missing" if method_name.nil?

        working_ctx = ctx
        outcome = host.new.public_send(method_name, working_ctx)
        result.merge(outcome: outcome, ctx: working_ctx)
      end

      private

      def invalid_result(errors)
        { body: nil, code: nil, inputs: [], outputs: [], validation_errors: errors }
      end
    end
  end
end
