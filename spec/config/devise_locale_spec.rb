# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Devise locale overrides", type: :config do
  it "applies the Devise 5.0 lowercase-email grammar fix" do
    message = I18n.t("devise.failure.invalid", authentication_keys: "email")
    expect(message).to eq("Invalid email or password.")
  end

  it "provides a non-empty sign-out confirmation message" do
    expect(I18n.t("devise.sessions.signed_out")).to be_a(String).and be_present
  end

  it "provides a non-empty reset-password instruction message" do
    expect(I18n.t("devise.passwords.send_instructions")).to be_a(String).and be_present
  end

  it "provides an unlock instruction message (lockable is enabled)" do
    expect(I18n.t("devise.unlocks.send_instructions")).to be_a(String).and be_present
  end
end
