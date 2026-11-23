# frozen_string_literal: true

require "digest"

module Billing
  module Onboarding
    module_function

    def call(customer)
      default = Plan.default_plan
      return Result.invalid(:fallback_configuration_invalid) unless default && Entitlements.fallback.reason.nil?

      # Permanent enrollment identity: backfill/repeated provisioning must never
      # resurrect an explicitly ended onboarding request.
      digest = Digest::SHA256.hexdigest("billing-onboarding:#{customer.id}")[0, 32]
      key = [digest[0, 8], digest[8, 4], digest[12, 4], digest[16, 4], digest[20, 12]].join("-")
      Current.set(customer: customer) do
        Activities::Subscribe.call(customer: customer, plan: default, request_key: key)
      end
    end
  end
end
