# frozen_string_literal: true

module Authentication
  class RegistrationsController < Devise::RegistrationsController
    include TenantContext
    include Authentication::PermitsUserParams

    layout "auth"

    before_action :check_auth_enabled
    before_action :check_registration_allowed, only: [:new, :create]

    # GET /:customer_id/auth/sign_up
    def new
      build_resource({})
      resource.customer_id = current_customer_id
    end

    # POST /:customer_id/auth/sign_up
    #
    # A taken address answers exactly like a new sign-up (same redirect,
    # flash and minimum duration); its owner may get a sign-in link instead.
    def create
      customer = current_customer || Customer.find(current_customer_id)
      started_at = Authentication::UniformTiming.start
      result = Authentication::RegisterMember.call(
        customer: customer,
        attributes: sign_up_params,
        request: request
      )
      self.resource = result.user

      if result.status == :quota_exceeded
        flash.now[:alert] = resource.errors[:base].last
        clean_up_passwords resource
        set_minimum_password_length
        render :new, status: :unprocessable_entity
        return
      end

      email_taken = resource.errors.of_kind?(:email, :taken)
      resource.errors.delete(:email, :taken)

      if result.status == :created || (email_taken && resource.errors.empty?)
        if email_taken
          Authentication::NotifyExistingMember.call(
            user: Authentication::User.find_by_normalized_email(resource.email), customer_id: customer.id
          )
        end
        Authentication::UniformTiming.pad(started_at)
        flash[:notice] = t("auth.flash.confirmation_sent", email: resource.email)
        respond_with resource, location: new_user_session_path
      else
        clean_up_passwords resource
        set_minimum_password_length
        render :new, status: :unprocessable_entity
      end
    end

    # GET /:customer_id/auth/edit
    def edit
      render :edit
    end

    # PUT/PATCH /:customer_id/auth
    def update
      self.resource = resource_class.to_adapter.get!(send(:"current_#{resource_name}").to_key)

      if update_resource(resource, account_update_params)
        set_flash_message!(:notice, :updated)
        bypass_sign_in resource, scope: resource_name
        respond_with resource, location: after_update_path_for(resource)
      else
        clean_up_passwords resource
        set_minimum_password_length
        render :edit, status: :unprocessable_entity
      end
    end

    protected

    def sign_up_params
      permitted_user_params(:first_name, :last_name, :email, :password, :password_confirmation)
    end

    def account_update_params
      permitted = permitted_user_params(:first_name, :last_name, :email, :password,
                                   :password_confirmation, :current_password)
      # Passwordless accounts (customer-signup admins) can set a password, but
      # must not swap email without current_password — reconfirmable is off.
      permitted = permitted.except(:email) unless resource.password_set?
      permitted
    end

    def update_resource(resource, params)
      return resource.update(params.except(:current_password)) unless resource.password_set?

      current_password = params.delete(:current_password)
      if params[:password].blank?
        params.delete(:password)
        params.delete(:password_confirmation) if params[:password_confirmation].blank?
      end

      # Devise's update_with_password only compares the digest. Verify before
      # assigning changes so Lockable cannot persist submitted credentials as
      # a side effect of updating its counters. Keep Devise's form errors.
      updated = if Authentication::PasswordVerification.authenticate(user: resource, password: current_password)
        resource.update(params)
      else
        resource.assign_attributes(params)
        resource.valid?
        resource.errors.add(:current_password, current_password.blank? ? :blank : :invalid)
        false
      end

      resource.clean_up_passwords
      updated
    end

    def after_update_path_for(resource)
      Authentication::LandingPath.for(resource)
    end

    private

    def check_auth_enabled
      cid = current_customer_id.presence || current_user&.customer_id
      return if FeatureModules::Module.enabled?(key: "authentication", customer_id: cid)

      if user_signed_in?
        redirect_to after_update_path_for(current_user), notice: t("auth.flash.auth_not_enabled")
      elsif cid.present?
        redirect_to admin_dashboard_path(cid), notice: t("auth.flash.auth_not_enabled")
      else
        redirect_to new_user_session_path, notice: t("auth.flash.auth_not_enabled")
      end
    end

    def check_registration_allowed
      return if Authentication::Settings.for(current_customer_id).signup_enabled?

      render "authentication/registrations/disabled", status: :ok
    end
  end
end
