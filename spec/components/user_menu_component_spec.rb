# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserMenuComponent, type: :component do
  let(:user) { build_stubbed(:user, customer: build_stubbed(:customer), email: "jane@acme.test", first_name: "Jane", last_name: "Doe") }
  let(:rendered) { render_inline(described_class.new(user: user, customer: user.customer)) }

  it "renders the user display name" do
    expect(rendered.text).to include("Jane Doe")
  end

  it "links to Devise-backed profile, change password, mfa setup, and sign out routes" do
    hrefs = rendered.css("a").map { |a| a.attr("href") }
    # "Change password" points at the profile edit page (which has the
    # password section) — NOT the Devise token-reset flow at
    # /auth/password/edit, which bounces a signed-in user to sign-in.
    expect(hrefs).to include(
      "/auth/edit",
      "/auth/edit#change-password",
      "/#{user.customer.id}/auth/mfa/setup"
    )
    expect(hrefs).not_to include("/auth/password/edit")
    sign_out_form = rendered.css("form[action='/auth/sign_out']").first
    expect(sign_out_form).not_to be_nil
    expect(sign_out_form.css("input[name=_method][value=delete]")).not_to be_empty
    expect(rendered.to_html).to include("Sign out")
  end
end
