# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::SurfaceCatalog do
  subject(:keys) { described_class.surfaces.map(&:key) }

  it "includes authentication/sessions with the locked defaults" do
    surface = described_class.find("authentication/sessions")
    expect(surface).to have_attributes(
      key: "authentication/sessions",
      group: :authentication,
      path: "/auth/sign_in",
      name_i18n_key: "captcha.surfaces.authentication_sessions"
    )
    expect(surface.fail_closed?).to eq(true)
  end

  it "does not emit authentication/sign_in_links as a separate key" do
    expect(keys).not_to include("authentication/sign_in_links")
  end

  it "does not emit public_pages" do
    expect(keys).not_to include("public_pages")
  end

  it "excludes admin and member routes" do
    expect(described_class.surfaces.map(&:path)).not_to include(a_string_including("/admin"), a_string_including("/member"))
    expect(keys).not_to include(a_string_matching(%r{(^|/)admin/}), a_string_matching(%r{(^|/)member/}))
  end

  it "includes payments/checkouts" do
    surface = described_class.find("payments/checkouts")
    expect(surface).to be_present
    expect(surface.group).to eq(:payments)
    expect(surface.path).to eq("/:customer_id/payments/checkout")
    expect(surface.fail_closed?).to eq(false)
  end

  it "includes authentication/registrations#sign_up" do
    surface = described_class.find("authentication/registrations#sign_up")
    expect(surface).to be_present
    expect(surface.path).to eq("/:customer_id/auth/sign_up")
    expect(surface.name_i18n_key).to eq("captcha.surfaces.authentication_registrations_sign_up")
  end

  it "matches member sign-up POST /:customer_id/auth to registrations#sign_up" do
    expect(described_class.matching_surface("/25685058/auth")&.key).to eq("authentication/registrations#sign_up")
  end

  # /auth/sign_up/resend re-sends the signup email and becomes reachable as
  # soon as session[:customer_signup_email] is set — i.e. after a single
  # captcha-solved POST to /auth/sign_up. Without the alias it matched no
  # surface at all, so the gate waved every resend through on a surface that
  # is explicitly marked fail_closed.
  it "matches the signup resend endpoint to the fail-closed signup surface" do
    surface = described_class.matching_surface("/auth/sign_up/resend")
    expect(surface&.key).to eq("authentication/customer_registrations")
    expect(surface.fail_closed?).to be(true)
  end

  it "matches the signup form itself to the same surface" do
    expect(described_class.matching_surface("/auth/sign_up")&.key)
      .to eq("authentication/customer_registrations")
  end

  # A token click is not a form post: gating it would break the emailed link
  # for every legitimate signup, and the token itself is the rate limit.
  it "leaves the signup confirm token endpoint uncatalogued" do
    expect(described_class.matching_surface("/auth/sign_up/confirm")).to be_nil
  end

  it "excludes denylisted webhook controllers" do
    expect(keys).not_to include(
      "payments/webhooks",
      "sms/webhooks",
      "emails/webhooks",
      "emails/tracking"
    )
  end

  it "returns nil from find for an unknown key" do
    expect(described_class.find("not/a/surface")).to be_nil
  end
end
