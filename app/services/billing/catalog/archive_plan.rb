# frozen_string_literal: true

module Billing
  module Catalog
    class ArchivePlan
      def self.call(plan:)
        Result.transaction(plan) do
          next Result.new(status: :unchanged, record: plan) if plan.archived_at
          next Result.invalid(:default_plan_required, record: plan) if plan.is_default?
          plan.update!(archived_at: Time.current, active: false)
          Result.new(status: :archived, record: plan)
        end
      end
    end
  end
end
