# frozen_string_literal: true

require "rails_helper"

RSpec.describe "authentication/passwords/new.html.erb", type: :view do
  let(:customer) { create(:customer) }
  let(:resource) { Authentication::User.new }

  before do
    stub_devise_view_context(resource, customer)
    render
  end

  it "renders the redesigned reset-link submit button copy" do
    expect(rendered).to include("Send reset link")
  end

  it "does not render the deprecated Devise 4.x copy" do
    expect(rendered).not_to include("Send reset instructions")
    expect(rendered).not_to include("Send me reset password instructions")
  end

  it "renders a password-reset form posting to user_password_path" do
    expect(rendered).to include("action=\"/auth/password\"")
    expect(rendered).to match(/method="post"/i)
  end

  it "renders the email input" do
    expect(rendered).to have_css('input[type="email"]')
  end

  it "renders a sign-in link back to the session path" do
    expect(rendered).to include("/auth/sign_in")
    expect(rendered).to include("Back to sign in")
  end
end
