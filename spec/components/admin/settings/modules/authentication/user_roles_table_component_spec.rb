# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Settings::Modules::Authentication::UserRolesTableComponent, type: :component do
  let_it_be(:customer) { create(:customer) }

  let(:system_role) { customer.roles.find_by!(key: "admin") }
  let(:custom_role) { create(:role, customer: customer, name: "Support Rep", key: "support_rep", system: false) }

  let(:user_with_roles) { create(:user, customer: customer, first_name: "Alice", last_name: "Wong", email: "alice@example.com") }
  let(:user_without_roles) { create(:user, customer: customer, first_name: "Bob", last_name: "Lee", email: "bob@example.com") }

  before do
    create(:users_role, user: user_with_roles, role: system_role)
    create(:users_role, user: user_with_roles, role: custom_role)

    stub_helpers = double(
      "helpers",
      admin_settings_modules_authentication_user_role_assignments_path: "/#{customer.id}/admin/settings/modules/authentication/user_role_assignments"
    )
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
render_inline(described_class.new(users: users, roles: roles, customer: customer))
  end

  let(:users) { [ user_with_roles, user_without_roles ] }
  let(:roles) { [ system_role, custom_role ] }


  it "renders a table row per user" do
    expect(page).to have_css("tbody tr", count: 2)
  end

  it "shows the display_name and email for each user" do
    expect(page).to have_text("Alice Wong")
    expect(page).to have_text("alice@example.com")
    expect(page).to have_text("Bob Lee")
    expect(page).to have_text("bob@example.com")
  end

  it "renders a badge per role for a user with roles" do
    expect(page).to have_css("td .badge", count: 2)
    expect(page).to have_css("td .badge", text: "Administrator")
    expect(page).to have_css("td .badge", text: "Support Rep")
  end

  it "renders the primary (badge-accent) variant badge for a system role" do
    expect(page).to have_css(".badge.badge-accent", count: 1)
  end

  it "renders the default variant badge for a non-system role" do
    expect(page).to have_css(".badge.badge-default", count: 1)
  end

  it "renders the empty-state text for a user with no roles" do
    expect(page).to have_text("No roles")
  end

  it "renders an Edit roles action button per user" do
    expect(page).to have_css("button", text: "Edit access", count: 2)
  end

  it "preserves assignment IDs, internal keys and custom descriptions in the existing dialog payload" do
    button = page.first("button[data-controller='user-role-dialog']")
    options = JSON.parse(button["data-user-role-dialog-roles-value"])
    expect(options.map { |role| role.fetch("id") }).to eq([system_role.id, custom_role.id])
    expect(options.last).to include("key" => "support_rep", "description" => custom_role.description)
    expect(JSON.parse(button["data-user-role-dialog-current-role-ids-value"])).to match_array(user_with_roles.roles.pluck(:id))
    expect(button["data-user-role-dialog-submit-url-value"]).to eq("/#{customer.id}/admin/settings/modules/authentication/user_role_assignments")
    expect(page).not_to have_css("[style]")
  end
end
