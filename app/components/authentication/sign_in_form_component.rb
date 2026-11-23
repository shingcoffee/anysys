# frozen_string_literal: true

module Authentication
  # Shared email+password sign-in form used by the public root and
  # GET /auth/sign_in. The surrounding auth shell supplies the heading, so the
  # form itself starts straight at the fields.
  class SignInFormComponent < ApplicationComponent
    def initialize(resource:, show_forgot_password: true, show_customer_signup: true)
      @resource = resource
      @show_forgot_password = show_forgot_password
      @show_customer_signup = show_customer_signup
    end

    attr_reader :resource, :show_forgot_password, :show_customer_signup
  end
end
