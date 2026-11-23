# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Settings::Modules::Authentication::RoleFormComponent, type: :component do
  let(:customer) { build_stubbed(:customer) }
  let(:new_role) { Role.new(customer: customer) }
  let(:persisted_role) { build_stubbed(:role, customer: customer, name: "Support", key: "support") }

  def build_component(role:) = described_class.new(role: role, customer: customer)

  before do
    stub_helpers = double(
      "helpers",
      admin_settings_modules_authentication_role_path: "/81721200/admin/settings/modules/authentication/roles/5",
      admin_settings_modules_authentication_roles_path: "/81721200/admin/settings/modules/authentication/roles",
      protect_against_forgery?: false
    )
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  describe "new role form" do
    before { render_inline(build_component(role: new_role)) }

    it "renders the Create Role submit button" do
      expect(page).to have_button("Create Role")
    end

    it "does not disable the key field" do
      expect(page).to have_field("role[key]", disabled: false)
    end

    it "autofocuses the name field" do
      expect(page).to have_css("input[name='role[name]'][autofocus]")
    end
  end

  describe "edit role form" do
    before { render_inline(build_component(role: persisted_role)) }

    it "renders the Update Role submit button" do
      expect(page).to have_button("Update Role")
    end

    it "disables the key field" do
      expect(page).to have_field("role[key]", disabled: true, visible: :all)
    end

    it "does not autofocus the name field" do
      expect(page).not_to have_css("input[name='role[name]'][autofocus]")
    end
  end

  describe "#submit_label" do
    it "returns Create Role for a new record" do
      expect(build_component(role: new_role).submit_label).to eq("Create Role")
    end

    it "returns Update Role for a persisted record" do
      expect(build_component(role: persisted_role).submit_label).to eq("Update Role")
    end
  end

  describe "#form_url" do
    it "uses the collection path for a new role" do
      component = build_component(role: new_role)
      stub_helpers = double(
        "helpers",
        admin_settings_modules_authentication_roles_path: "/81721200/admin/settings/modules/authentication/roles"
      )
      allow(component).to receive(:helpers).and_return(stub_helpers)
      expect(component.form_url).to eq("/81721200/admin/settings/modules/authentication/roles")
    end

    it "uses the member path for a persisted role" do
      component = build_component(role: persisted_role)
      stub_helpers = double(
        "helpers",
        admin_settings_modules_authentication_role_path: "/81721200/admin/settings/modules/authentication/roles/5"
      )
      allow(component).to receive(:helpers).and_return(stub_helpers)
      expect(component.form_url).to eq("/81721200/admin/settings/modules/authentication/roles/5")
    end
  end
end
