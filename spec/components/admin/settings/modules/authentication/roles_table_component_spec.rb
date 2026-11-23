require "rails_helper"

RSpec.describe Admin::Settings::Modules::Authentication::RolesTableComponent, type: :component do
  let(:customer) { build_stubbed(:customer, id: 81721200) }
  let(:admin_role) { build_stubbed(:role, customer: customer, key: "admin", system: true) }
  let(:custom_role) { build_stubbed(:role, customer: customer, name: "Support", key: "support_internal", system: false) }

  before do
    [admin_role, custom_role].each { |role| allow(role).to receive_message_chain(:users, :size).and_return(3) }
    render_inline(described_class.new(rows: [admin_role, custom_role], pagination: {}, params: {}, customer: customer))
  end

  it "links readable names to role details and explains scope" do
    expect(page).to have_link("Administrator", href: "/#{customer.id}/admin/settings/modules/authentication/roles/#{admin_role.id}")
    expect(page).to have_text("Administrative access within this organization.")
    expect(page).to have_text("Built-in role")
    expect(page).not_to have_text("support_internal")
  end

  it "retains existing permissions and custom edit/delete actions with built-in restrictions" do
    within("table") do
      expect(page).to have_link("Permissions", count: 2)
      expect(page).to have_link("Edit", count: 1)
      expect(page).to have_link("Delete", count: 1)
    end
    expect(page).to have_css("[data-turbo-confirm]")
    expect(page).not_to have_link(href: "/#{customer.id}/admin/settings/modules/authentication/roles/#{admin_role.id}/edit")
  end
end
