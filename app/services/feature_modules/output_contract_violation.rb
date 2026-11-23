# frozen_string_literal: true

module FeatureModules
  # Module passed an invalid output payload to Complete.
  class OutputContractViolation < Error
    attr_reader :contract_errors

    def initialize(message = nil, contract_errors: {})
      super(message)
      @contract_errors = contract_errors
    end
  end
end
