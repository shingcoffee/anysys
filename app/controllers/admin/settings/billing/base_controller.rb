# frozen_string_literal: true

require "ostruct"

module Admin
  module Settings
    module Billing
      # Shared base for consolidated billing customer-settings controllers.
      #
      # Placed under /:cid/admin/settings/billing/* (first-class settings area).
      # Authorization is enforced globally by RouteAuthorization — the /admin/
      # path prefix guarantees that only admin or owner users reach these
      # controllers. Individual controllers must not add a redundant
      # before_action :authenticate_user! or role check.
      #
      # All subclasses must scope every record lookup to the current customer via
      # for_current_customer (TenantScoped) or an explicit customer_id condition
      # to prevent cross-tenant leakage.
      class BaseController < ApplicationController
        include ::Billing::Pagination
        include ::Billing::ControllerPresentation

        dashboard_menu_item :settings

        helper_method :current_billing_tab_counts

        private

        def current_billing_tab_counts
          @billing_tab_counts ||= billing_tab_counts(current_customer)
        end

        # Stored live status is a uniqueness/worker predicate, not authority for
        # a logically ended enrollment. This read never performs expiration.
        def live_subscription
          return @live_subscription if instance_variable_defined?(:@live_subscription)
          @live_subscription = ::Billing::Entitlements.current_subscription(customer: current_customer)
        end

        def billing_currency
          live_subscription ? live_subscription.currency : ::Billing::CurrencyResolver.for_customer(current_customer)
        end

        def assign_subscription_overview
          @subscription = live_subscription
          @latest_subscription = ::Billing::Subscription.for_current_customer
                                  .order(created_at: :desc, id: :desc).first
          @pending_plan_change = pending_plan_change
          @plans = ::Billing::Plan.active.includes(:plan_limits).ordered
          @enabled_items = ::Billing::CountableItem.enabled.ordered
          @currency = billing_currency
          @entitlements = ::Billing::Entitlements.for(customer: current_customer)
          @usage = billing_usage(current_customer)
          @coupon_benefit = billing_coupon_benefit(@subscription, pending_change: @pending_plan_change)
          @subscription_actions = billing_subscription_actions(@subscription, pending_change: @pending_plan_change)
          @can_cancel = @subscription_actions.fetch(:can_cancel)
          @can_resume = @subscription_actions.fetch(:can_resume)
          recovery_invoices = ::Billing::Invoice.for_current_customer.where(status: %w[open uncollectible])
                              .order(created_at: :desc, id: :desc).to_a
          @recovery = billing_subscription_recovery(@subscription, invoices: recovery_invoices,
                                                    entitlements: @entitlements, actions: @subscription_actions)
          @one_time_payment = billing_subscription_one_time_payment(@subscription, invoices: recovery_invoices)
          @one_time_open ||= false
          assign_billing_methods
          unless instance_variable_defined?(:@request_key)
            @request_key = params.permit(:request_key)[:request_key] || @pending_plan_change&.request_key || SecureRandom.uuid
          end
          @form ||= subscription_form(plan_code: @review_plan&.code, coupon_code: nil, request_key: @request_key)
          @contract = @form
          assign_plan_review if @review_plan
        end

        def assign_billing_methods
          @subscription = live_subscription
          @currency = billing_currency
          @payment_methods = ::Billing::PaymentMethod.for_current_customer
                             .order(created_at: :desc, id: :desc)
          @payment_method = @payment_methods.default_method.first
          assign_provider_options
        end

        def assign_provider_options
          @provider_options = ::Billing::PresentationFacts.provider_options(customer: current_customer, currency: @currency)
          @available_providers = @provider_options.select { |option| option.fetch(:enabled) }.map { |option| option.fetch(:key) }
        end

        def assign_plan_review
          return unless @subscription
          preview = @review_preview || ::Billing::PlanChangePolicy.preview(subscription: @subscription, new_plan: @review_plan)
          @plan_review = preview.slice(:kind, :effective_at, :currency, :subtotal_cents, :tax_cents,
                                       :total_cents, :allowed, :reason).merge(
            plan: @review_plan, plan_code: @review_plan.code, interval: @review_plan.interval,
            calculated_at: Time.current, reason_key: billing_reason_key(preview[:reason])
          )
        end

        def pending_plan_change
          return unless live_subscription
          ::Billing::PlanChange.for_current_customer
            .where(billing_subscription_id: live_subscription.id, status: %w[awaiting_payment scheduled])
            .order(created_at: :desc, id: :desc).first
        end

        def subscription_form(attributes)
          klass = live_subscription ? ::Billing::Contracts::ChangePlan : ::Billing::Contracts::Subscribe
          klass.new(OpenStruct.new(attributes.merge(currency: billing_currency)))
        end

        def assign_billing_result(result)
          remove_instance_variable(:@live_subscription) if instance_variable_defined?(:@live_subscription)
          @result = result
          @form = result.form if result.form
          @contract = @form
          @errors = result.errors
        end

        def billing_failure_status(result)
          %i[conflict blocked exhausted skipped].include?(result.status) ? :conflict : :unprocessable_entity
        end

        def billing_failure_message(result)
          t(billing_reason_key(result.reason) || "admin_settings.flash.billing.command_invalid")
        end

        def render_subscription_failure(result)
          assign_billing_result(result)
          respond_to do |format|
            format.html do
              assign_subscription_overview
              flash.now[:alert] = billing_failure_message(result)
              render "admin/settings/billing/subscriptions/show", status: billing_failure_status(result)
            end
            format.json do
              render json: { status: result.status, reason: result.reason, error: billing_failure_message(result) },
                     status: billing_failure_status(result)
            end
          end
        end

        def valid_billing_request_key?(value)
          value.is_a?(String) && value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
        end
      end
    end
  end
end
