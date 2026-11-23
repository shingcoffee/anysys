# frozen_string_literal: true

module Billing
  module Catalog
    class SavePlan
      def self.call(plan:, params:, limits:)
        Result.transaction(plan) do
          form = Contracts::Plan.new(plan)
          attributes = params.to_h.stringify_keys.except("limits", "archived_at")
          submitted = form.limits.merge(limits.to_h.stringify_keys)
          unless form.validate(attributes.merge("limits" => submitted))
            next Result.invalid(:validation_failed, record: plan, form: form, errors: form.errors.messages)
          end
          if plan.is_default? && !::ActiveModel::Type::Boolean.new.cast(form.is_default)
            form.errors.add(:is_default, I18n.t("admin_settings.errors.validations.default_plan_required"))
            next Result.invalid(:default_plan_required, record: plan, form: form, errors: form.errors.messages)
          end
          Plan.where(is_default: true).where.not(id: plan.id).update_all(is_default: false) if ::ActiveModel::Type::Boolean.new.cast(form.is_default)
          form.sync
          plan.save!
          AssignPlanLimits.call(plan: plan, limits: form.normalized_limits)
          Result.new(status: :saved, record: plan, form: form)
        end
      end
    end
  end
end
