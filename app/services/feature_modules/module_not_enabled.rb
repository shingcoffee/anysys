# frozen_string_literal: true

module FeatureModules
  # Triggering page references a module the customer has not enabled.
  class ModuleNotEnabled < Error; end
end
