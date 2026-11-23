# frozen_string_literal: true

module CodeGeneratorHelpers
  # The formatted step method a generator emits for +config+ (its sample input
  # by default), named `test_step`. Raises when the config does not validate so
  # a golden expectation never silently compares against nil.
  def generated_step(config = described_class.sample_input, generator: described_class, context: {})
    result = CodeGenerators::TestRunner.run(generator, config: config, context: context)
    errors = result[:validation_errors].map { |error| error.respond_to?(:message) ? error.message : error.to_s }
    raise ArgumentError, "#{generator.generator_name} rejected the config: #{errors.join('; ')}" if errors.any?

    result[:code]
  end
end

RSpec.configure do |config|
  config.include CodeGeneratorHelpers, file_path: %r{spec/services/code_generators/}
end
