# frozen_string_literal: true

class UserMenuComponent < ApplicationComponent
  def initialize(user:, customer:)
    @user = user
    @customer = customer
  end

  attr_reader :user, :customer

  def display_name
    [user.first_name, user.last_name].compact.join(" ").presence || user.email
  end

  def profile_path  = "/auth/edit"
  # The logged-in "change password" flow lives on the profile edit page
  # (it has a dedicated password section). The Devise /auth/password/edit
  # route is the token-based RESET flow and bounces a signed-in user to
  # sign-in, so it must not be linked here.
  def password_path = "/auth/edit#change-password"
  def mfa_path      = "/#{customer.id}/auth/mfa/setup"
  def sign_out_path = "/auth/sign_out"
end
