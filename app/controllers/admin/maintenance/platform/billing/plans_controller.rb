# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Billing
        class PlansController < BaseController
          before_action :set_plan, only: %i[show edit update destroy]
          before_action :set_items

          def index
            @plans = paginate_billing(::Billing::Plan.ordered.includes(:plan_limits))
          end

          def show
          end

          def new
            @plan = ::Billing::Plan.new
            @form = @contract = ::Billing::Contracts::Plan.new(@plan)
          end

          def edit
            @form = @contract = ::Billing::Contracts::Plan.new(@plan)
          end

          def create
            @plan = ::Billing::Plan.new
            save_plan(:new, "plan_created")
          end

          def update
            save_plan(:edit, "plan_updated")
          end

          def destroy
            result = ::Billing::Catalog::ArchivePlan.call(plan: @plan)
            unless %i[archived unchanged].include?(result.status)
              @plans = paginate_billing(::Billing::Plan.ordered.includes(:plan_limits))
              return render_billing_failure(result, :index)
            end
            redirect_to admin_maintenance_platform_billing_plans_path(current_customer_id), status: :see_other,
                        notice: t("maint_platform.flash.billing.plan_archived")
          end

          private

          def save_plan(template, notice_key)
            @submitted_limits = params.require(:billing_plan).permit(limits: {})[:limits]&.to_h || {}
            result = ::Billing::Catalog::SavePlan.call(plan: @plan, params: plan_params.to_h, limits: @submitted_limits)
            assign_billing_result(result)
            return render_billing_failure(result, template) unless result.status == :saved
            @plan = result.record
            redirect_to admin_maintenance_platform_billing_plans_path(current_customer_id), status: :see_other,
                        notice: t("maint_platform.flash.billing.#{notice_key}", name: @plan.name)
          end

          def set_plan
            @plan = ::Billing::Plan.find(params[:id])
          end

          def set_items
            # Core quotas stay on the plan form even when their catalog row is disabled.
            # A blank value is unlimited; hiding the field made a new plan look like it had no caps.
            registry_keys = ::Billing::Countable::Registry.keys
            @items = ::Billing::CountableItem.where(enabled: true).or(::Billing::CountableItem.where(key: registry_keys)).ordered
          end

          def plan_params
            params.require(:billing_plan).permit(:code, :name, :description, :amount_usd, :amount_cny,
                                                 :interval, :trial_days, :active, :is_default, :position)
          end
        end
      end
    end
  end
end
