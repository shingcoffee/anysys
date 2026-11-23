# frozen_string_literal: true

require "rails_helper"

RSpec.describe "authentication/registrations/new.html.erb", type: :view do
  let(:customer) { create(:customer) }
  let(:resource) { Authentication::User.new(customer_id: customer.id) }

  before do
    stub_devise_view_context(resource, customer)
    render
  end

  it "renders the sign-up title" do
    expect(rendered).to include("Create your account")
  end

  it "posts to the user_registration path" do
    expect(rendered).to include("action=\"/#{customer.id}/auth\"")
    expect(rendered).to match(/method="post"/i)
  end

  it "renders first_name, last_name, email, password, password_confirmation inputs" do
    %w[first_name last_name email password password_confirmation].each do |field|
      expect(rendered).to match(/name="user\[#{field}\]"/)
    end
  end

  it "links back to the sign-in page" do
    expect(rendered).to include("/auth/sign_in")
  end
end
