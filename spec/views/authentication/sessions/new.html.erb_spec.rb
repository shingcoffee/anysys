# frozen_string_literal: true

require "rails_helper"

RSpec.describe "authentication/sessions/new.html.erb", type: :view do
  let(:customer) { create(:customer) }
  let(:resource) { Authentication::User.new }

  before do
    stub_devise_view_context(resource, customer)
    # Stub the auth_settings helper introduced in Task 12. The sessions/new
    # template conditionally renders sign-up/forgot-password links based on
    # these toggles.
    without_partial_double_verification do
      allow(view).to receive(:auth_settings).and_return(
        instance_double(Authentication::Settings,
                        signup_enabled?: true,
                        password_reset_enabled?: true)
      )
    end
    render
  end

  it "renders the sign-in title" do
    expect(rendered).to include("Welcome back.")
  end

  it "posts to the user_session path for the customer" do
    expect(rendered).to include("action=\"/auth/sign_in\"")
  end

  it "renders the email, password, and remember-me inputs" do
    expect(rendered).not_to match(/name="customer_number"/)
    expect(rendered).to match(/name="user\[email\]"/)
    expect(rendered).to match(/name="user\[password\]"/)
    expect(rendered).to match(/name="user\[remember_me\]"/)
  end

  it "renders an email sign-in link submit" do
    expect(rendered).to have_css('button[type="submit"][name="intent"][value="sign_in_link"]',
                                text: "Email me a sign-in link")
  end
end
