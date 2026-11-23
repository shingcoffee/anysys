# frozen_string_literal: true

module FeatureModules
  module Email
    class Provisioner
      def self.call(customer)
        # Email no longer provisions per-tenant streams or other records.
      end

      def self.revoke(customer)
        # Email records are tenant-scoped and deleted via FK cascade.
      end
    end
  end
end
