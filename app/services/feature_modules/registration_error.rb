# frozen_string_literal: true

module FeatureModules
  # Registration DSL used incorrectly (unknown route, malformed contract, etc.).
  class RegistrationError < Error; end
end
