# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member::Profiles", type: :request do
  let(:customer) { create(:customer) }
  let(:member)   { create(:user, :member, customer: customer, password: "password123") }
  let(:edit_path) { "/#{customer.id}/member/profile/edit" }
  let(:path)      { "/#{customer.id}/member/profile" }

  before do
    enable_module!("authentication", customer, name: "Authentication")
    sign_in member
  end

  def patch_profile(**attrs)
    patch path, params: { member_profiles_update_contract: attrs }
  end

  it "updates name without current_password when email is unchanged" do
    patch_profile(first_name: "Linnea", last_name: member.last_name, email: member.email)
    expect(response).to redirect_to(path)
    expect(member.reload.first_name).to eq("Linnea")
  end

  it "does not change email without current_password" do
    original = member.email
    patch_profile(first_name: member.first_name, last_name: member.last_name, email: "hijacked@example.com")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(member.reload.email).to eq(original)
  end

  it "changes email when current_password is correct" do
    patch_profile(
      first_name: member.first_name, last_name: member.last_name,
      email: "new@example.com", current_password: "password123"
    )
    expect(response).to redirect_to(path)
    expect(member.reload.email).to eq("new@example.com")
  end

  it "renders the current-password field on the edit form" do
    get edit_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Required when changing your email.")
  end

  it "points Sign out at Devise /auth/sign_out, not a tenant-prefixed 404" do
    get path
    expect(response.body).to include('href="/auth/sign_out"')
    expect(response.body).not_to include("/#{customer.id}/auth/sign_out")
  end

  it "does not 500 when the profile payload is posted as an array" do
    expect {
      patch path, params: { member_profiles_update_contract: ["not-a-hash"] }
    }.not_to change { member.reload.first_name }

    expect(response).to have_http_status(:bad_request)
  end
end
