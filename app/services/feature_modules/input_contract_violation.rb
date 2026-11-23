# frozen_string_literal: true

module FeatureModules
  # input_mapping produced a payload that fails the module's input_contract.
  class InputContractViolation < Error
    attr_reader :contract_errors

    def initialize(message = nil, contract_errors: {})
      super(message)
      @contract_errors = contract_errors
    end
  end
end
