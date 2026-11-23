# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::SignInFormComponent, type: :component do
  let(:resource) { Authentication::User.new }

  def render_form(**)
    render_inline(described_class.new(resource: resource, **))
  end

  it "posts the password form to /auth/sign_in" do
    render_form
    expect(page).to have_css('form[action="/auth/sign_in"]')
    expect(page).to have_css('form[data-turbo="false"]')
    expect(page).to have_css('input[type="submit"][value="Sign in"]')
    expect(page).to have_css('button[type="submit"][name="intent"][value="sign_in_link"]',
                            text: "Email me a sign-in link")
    expect(page).to have_text("or")
    expect(page).not_to have_css('[formaction="/auth/sign_in_link"]')
    expect(page).to have_link(I18n.t("auth.sessions.create_account_link"), href: "/auth/sign_up")
  end

  it "renders email, password, and remember-me" do
    render_form
    expect(page).to have_field("Email")
    expect(page).to have_field("Password")
    expect(page).to have_field("Remember me")
  end

  it "leaves the heading to the auth shell and the fields unplaceheld" do
    render_form
    expect(page).not_to have_css("h1, h2")
    expect(page).not_to have_css("input[placeholder]")
  end

  it "styles the buttons with the shared member accent pair" do
    render_form
    expect(page).to have_css('input[type="submit"].btn-member')
    expect(page).to have_css('button[value="sign_in_link"].btn-member-secondary')
  end

  it "shows forgot-password by default" do
    render_form
    expect(page).to have_link(I18n.t("auth.sessions.forgot_password"))
  end

  it "hides forgot-password when asked" do
    render_form(show_forgot_password: false)
    expect(page).not_to have_link(I18n.t("auth.sessions.forgot_password"))
  end

  it "does not render the captcha widget on the sign-in form" do
    Captcha::Providers::Aliyun
    create(:captcha_provider_settings, enabled: true)
    render_form
    expect(page).not_to have_css("input[name='captcha_verify_param']")
  end
end
