# frozen_string_literal: true

module Member
  module Payments
    # Member self-service: manage vaulted card payment methods.
    #
    # Authorization: member role is enforced by RouteAuthorization (URL gate)
    # and Member::BaseController#authorize_owned! (record gate).
    # Every record action MUST scope by BOTH customer_id (TenantScoped) AND
    # user_id (via .for_user(current_user.id)) to enforce member isolation.
    #
    # This is NOT a preview surface — admin users are NOT admitted to any action.
    class PaymentMethodsController < Member::BaseController
      before_action :require_payments_module!
      before_action :set_payment_method, only: :destroy

      def index
        # Only confirmed cards (real PSP token). A vault flow still awaiting its
        # setup_intent.succeeded webhook holds a "pending:" placeholder token and
        # must not surface as a usable saved card.
        @payment_methods = scoped_methods.chargeable.order(created_at: :desc)

        render ::Payments::Member::PaymentMethodsComponent.new(
          payment_methods:  @payment_methods,
          setup_intent_url: setup_intent_member_payments_payment_methods_path(current_customer_id),
          create_url:       member_payments_payment_methods_path(current_customer_id),
          destroy_url_proc: ->(pm) { member_payments_payment_method_path(current_customer_id, pm) },
          publishable_key:  stripe_publishable_key
        )
      end

      # GET /new — reserved as the "Add card" entry point; the Stripe Element
      # is embedded on the index page so new redirects back there.
      def new
        redirect_to member_payments_payment_methods_path(current_customer_id)
      end

      # POST /setup_intent — creates a PSP SetupIntent and returns its
      # client_secret so the browser can confirm the card via Stripe.js.
      # The gateway call is safe to repeat: duplicate vault flows for the same
      # user result in separate SetupIntent rows; the webhook deduplicates later.
      def setup_intent
        result = ::Payments::Activities::VaultCard.call(
          customer:   current_customer,
          user:       current_user,
          provider:   "stripe",
          return_url: member_payments_payment_methods_url(customer_id: current_customer_id)
        )
        render json: {
          client_secret:     result[:client_secret],
          payment_method_id: result[:payment_method].id
        }
      rescue StandardError => e
        Rails.logger.warn("[member.payment_methods.setup_intent] #{e.class}: #{e.message}")
        render json: { error: t("member.flash.payment_methods.setup_failed") },
               status: :unprocessable_entity
      end

      # POST /payment_methods — called by the Stripe.js confirm flow after the
      # SetupIntent succeeds. The PSP pushes the final card details (brand/last4/
      # exp) through the setup_intent.succeeded webhook, which backfills them.
      # This action's job is to find-or-confirm the pending PaymentMethod row
      # and redirect to the listing.
      def create
        psp_pm_id = params[:payment_method_id].to_s
        # Only confirm a row the webhook (or a prior confirm) already bound to
        # this PSP id. Never stamp client-supplied ids onto a pending: placeholder
        # — that would make a fake token chargeable before setup_intent.succeeded.
        pm = psp_pm_id.present? ? scoped_methods.find_by(psp_payment_method_id: psp_pm_id) : nil

        if pm
          redirect_to member_payments_payment_methods_path(current_customer_id),
                      notice: t("member.flash.payment_methods.saved")
        elsif scoped_methods.where("psp_payment_method_id LIKE ?", "pending:%").exists?
          redirect_to member_payments_payment_methods_path(current_customer_id),
                      notice: t("member.flash.payment_methods.saved")
        else
          redirect_to member_payments_payment_methods_path(current_customer_id),
                      alert: t("member.flash.payment_methods.confirm_failed")
        end
      end

      # DELETE /payment_methods/:id — detaches the PSP token and soft-removes
      # the vault row. Guarded by set_payment_method which 404s for records
      # not belonging to this member in this tenant.
      def destroy
        ::Payments::Gateway.detach_token(
          customer:       current_customer,
          payment_method: @payment_method
        )
        @payment_method.mark_removed!
        redirect_to member_payments_payment_methods_path(current_customer_id),
                    notice: t("member.flash.payment_methods.removed")
      rescue ::Payments::Errors::Error => e
        Rails.logger.warn("[member.payment_methods.destroy] detach_token failed: #{e.message}")
        @payment_method.mark_removed!
        redirect_to member_payments_payment_methods_path(current_customer_id),
                    notice: t("member.flash.payment_methods.removed")
      end

      private

      def require_payments_module!
        return if FeatureModules::Module.enabled?(key: "payment", customer_id: current_customer.id)

        head :not_found
      end

      # Scope payment methods to the current tenant AND the current member.
      # customer_id scoping is provided by TenantScoped (.for_current_customer);
      # .for_user adds the user_id guard required by AGENTS.md member rules.
      def scoped_methods
        ::Payments::PaymentMethod
          .for_current_customer
          .for_user(current_user.id)
      end

      def set_payment_method
        @payment_method = scoped_methods.find(params[:id])
      end

      # Same (customer, provider, mode) lookup VaultCard uses via Payments::Gateway
      # (CredentialResolver's default mode tracks Rails.env.production?). A tenant
      # may have both a sandbox and a production Stripe account active at once;
      # grabbing "whichever active row comes back first" can hand Stripe.js a
      # publishable key from a different mode than the SetupIntent client_secret.
      def stripe_publishable_key
        ::Payments::CredentialResolver.call(customer: current_customer, provider: "stripe")
                                       .credential(:publishable_key)
      rescue ::Payments::Errors::CredentialsMissing
        nil
      end
    end
  end
end
