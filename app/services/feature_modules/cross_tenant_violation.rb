# frozen_string_literal: true

module FeatureModules
  # Session customer_id does not match Current.customer_id.
  class CrossTenantViolation < Error; end
end
