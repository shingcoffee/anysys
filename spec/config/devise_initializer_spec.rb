# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Devise initializer", type: :config do
  it "uses :unprocessable_content as the responder error status (Devise 5.0 / Rack 3.1+)" do
    expect(Devise.responder.error_status).to eq(:unprocessable_content)
  end

  it "uses :see_other as the responder redirect status" do
    expect(Devise.responder.redirect_status).to eq(:see_other)
  end

  it "configures password length range 8..128" do
    expect(Devise.password_length).to eq(8..128)
  end

  it "configures case-insensitive and stripped email as the authentication key" do
    aggregate_failures do
      expect(Devise.authentication_keys).to eq([:email])
      expect(Devise.case_insensitive_keys).to eq([:email])
      expect(Devise.strip_whitespace_keys).to eq([:email])
    end
  end

  it "uses cheap stretches in the test environment" do
    expect(Devise.stretches).to eq(1)
  end

  it "expires all remember-me tokens on sign out" do
    expect(Devise.expire_all_remember_me_on_sign_out).to be(true)
  end

  it "configures lockable with failed-attempts strategy" do
    aggregate_failures do
      expect(Devise.lock_strategy).to eq(:failed_attempts)
      expect(Devise.unlock_keys).to eq([:email])
      expect(Devise.unlock_strategy).to eq(:time)
      expect(Devise.maximum_attempts).to eq(10)
      expect(Devise.unlock_in).to eq(30.minutes)
    end
  end

  it "configures reset_password_within to 6 hours" do
    expect(Devise.reset_password_within).to eq(6.hours)
  end

  it "signs out via DELETE" do
    expect(Devise.sign_out_via).to eq(:delete)
  end

  it "skips session storage for http_auth" do
    expect(Devise.skip_session_storage).to eq([:http_auth])
  end

  it "does not require reconfirmation (confirmable not used)" do
    expect(Devise.reconfirmable).to be(false)
  end

  it "enables paranoid mode to prevent user enumeration" do
    expect(Devise.paranoid).to be(true)
  end
end
