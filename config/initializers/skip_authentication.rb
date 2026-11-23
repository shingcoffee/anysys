# frozen_string_literal: true

# Disable authentication for fast iteration in development.
# Opt-in via SKIP_AUTH=1 (default off). Hard-fails if reached outside
# development so a misconfigured RAILS_ENV can never disable auth in prod.

return unless ENV["SKIP_AUTH"].to_s == "1"

raise "SKIP_AUTH may only be enabled in development (got #{Rails.env})" unless Rails.env.development?

Rails.application.config.to_prepare do
  ApplicationController.class_eval do
    # Accept any args/kwargs: Devise calls this as `authenticate_user!(force: true)`
    # from `authenticate_scope!` (e.g. the registrations edit/update actions),
    # so a 0-arity stub raises ArgumentError and 500s those pages under SKIP_AUTH.
    def authenticate_user!(*, **)
      true
    end

    def current_user
      @current_user ||= begin
        customer = Current.customer || Customer.find_by(id: 81721200)
        Authentication::User.find_by(customer: customer) || Authentication::User.first
      end
    end

    def user_signed_in?
      true
    end

    def enforce_mfa!
      true
    end
  end
end
