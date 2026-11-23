# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Settings::Modules::Authentication::GrantsEditorComponent, type: :component do
  let(:customer) { build_stubbed(:customer) }

  let(:contact_descriptor) do
    AccessPoints::Descriptor.new(
      subject_type: "Entity",
      subject_key: "contact",
      subject_id: nil,
      actions: %i[read update],
      group_key: "entities",
      label: "Contact",
      description: "Contact entity"
    )
  end

  let(:donation_descriptor) do
    AccessPoints::Descriptor.new(
      subject_type: "Entity",
      subject_key: "donation",
      subject_id: nil,
      actions: %i[read create update destroy],
      group_key: "entities",
      label: "Donation",
      description: "Donation entity"
    )
  end

  let(:catalog) do
    double(
      "catalog",
      groups: [
        { key: "entities", label: "Entities", descriptors: [ contact_descriptor, donation_descriptor ] }
      ]
    )
  end

  let(:granted_keys) { [ "Entity:contact::read" ] }

  def build_component(role:, granted_keys: self.granted_keys)
    described_class.new(role: role, catalog: catalog, granted_keys: granted_keys, customer: customer)
  end

  before do
    stub_helpers = double(
      "helpers",
      admin_settings_modules_authentication_role_grants_path: "/81721200/admin/settings/modules/authentication/roles/5/grants"
    )
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  describe "unlocked role" do
    let(:role) { build_stubbed(:role, customer: customer, locked_grants: false) }

    before { render_inline(build_component(role: role)) }

    it "renders the group label" do
      expect(page).to have_text("Entities")
    end

    it "renders a checkbox per action for each descriptor" do
      # contact: read, update (2) + donation: read, create, update, destroy (4) = 6
      expect(page).to have_css("input.grants-checkbox", count: 6)
    end

    it "checks the checkbox for a granted key" do
      checked_box = page.find("input[data-grants-editor-subject-key-param='contact'][data-grants-editor-action-param='read']")
      expect(checked_box[:checked]).to be_truthy
    end

    it "does not check a checkbox for a non-granted key" do
      unchecked_box = page.find("input[data-grants-editor-subject-key-param='contact'][data-grants-editor-action-param='update']")
      expect(unchecked_box[:checked]).to be_falsey
    end

    it "does not disable checkboxes" do
      expect(page).not_to have_css("input.grants-checkbox[disabled]")
    end

    it "does not render the locked warning banner" do
      expect(page).not_to have_text("Reserved system role")
    end

    it "renders the Grant all / Revoke all group actions" do
      expect(page).to have_button("Grant all")
      expect(page).to have_button("Revoke all")
    end
  end

  describe "locked role" do
    let(:role) { build_stubbed(:role, customer: customer, locked_grants: true) }

    before { render_inline(build_component(role: role)) }

    it "renders the locked warning banner" do
      expect(page).to have_text("Permissions are read-only")
    end

    it "disables all checkboxes" do
      expect(page).to have_css("input.grants-checkbox[disabled]", count: 6)
    end

    it "does not render the Grant all / Revoke all group actions" do
      expect(page).not_to have_button("Grant all")
      expect(page).not_to have_button("Revoke all")
    end

    it "does not render the sticky save bar" do
      expect(page).not_to have_css("[data-grants-editor-target='saveBar']")
    end
  end

  describe "#total_actions and #total_granted" do
    let(:role) { build_stubbed(:role, customer: customer, locked_grants: false) }

    it "counts total actions across all descriptors" do
      component = build_component(role: role)
      expect(component.total_actions).to eq(6)
    end

    it "counts only the granted actions" do
      component = build_component(role: role, granted_keys: [ "Entity:contact::read", "Entity:donation::create" ])
      expect(component.total_granted).to eq(2)
    end

    it "counts zero granted when granted_keys is empty" do
      component = build_component(role: role, granted_keys: [])
      expect(component.total_granted).to eq(0)
    end
  end

  describe "#granted? and #grant_key" do
    let(:role) { build_stubbed(:role, customer: customer, locked_grants: false) }
    let(:component) { build_component(role: role) }

    it "builds the composite grant key" do
      expect(component.grant_key(contact_descriptor, :read)).to eq("Entity:contact::read")
    end

    it "is granted when the key is present in granted_keys" do
      expect(component.granted?(contact_descriptor, :read)).to be(true)
    end

    it "is not granted when the key is absent" do
      expect(component.granted?(contact_descriptor, :update)).to be(false)
    end
  end

  describe "#locked?" do
    it "delegates to role.locked_grants?" do
      locked_role = build_stubbed(:role, customer: customer, locked_grants: true)
      unlocked_role = build_stubbed(:role, customer: customer, locked_grants: false)

      expect(build_component(role: locked_role).locked?).to be(true)
      expect(build_component(role: unlocked_role).locked?).to be(false)
    end
  end

  it "shows the owner's effective all-access state without a zero-grants counter" do
    role = build_stubbed(:role, customer: customer, key: "owner", locked_grants: true)
    render_inline(build_component(role: role, granted_keys: []))
    expect(page).to have_text("All resources and actions")
    expect(page).to have_css("input.grants-checkbox[checked][disabled]", count: 6)
    expect(page).not_to have_css("[data-grants-editor-target='counter']")
    expect(page).not_to have_css("[data-grants-editor-target='groupCount']")
    expect(page).not_to have_button("Save", visible: :all)
  end

  it "keeps zero configured permissions truthful for other locked roles" do
    role = build_stubbed(:role, customer: customer, key: "member", locked_grants: true)
    render_inline(build_component(role: role, granted_keys: []))
    expect(page).to have_text("0 / 6 granted")
    expect(page).not_to have_text("All resources and actions")
    expect(page).not_to have_css("input.grants-checkbox[checked]")
  end

  it "displays route metadata while preserving authorization keys in the payload" do
    role = build_stubbed(:role, customer: customer, locked_grants: false)
    route = AccessPoints::Descriptor.new(subject_type: "Route", subject_key: "admin/settings/modules/authentication/roles", subject_id: nil,
      actions: [:read], group_key: "settings", label: "Roles")
    route_catalog = double(groups: [{ key: "settings", label: "Settings", descriptors: [route] }])
    render_inline(described_class.new(role: role, customer: customer, granted_keys: [], catalog: route_catalog))
    expect(page).to have_text("Roles & permissions")
    expect(page).not_to have_text("admin/settings/modules/authentication/roles")
    expect(page).to have_css("input[data-grants-editor-subject-key-param='admin/settings/modules/authentication/roles']")
    expect(page).not_to have_css("[style]", visible: :all)
  end

  it "renders qualified Chinese labels as the shared display, search and review contract" do
    keys = %w[captcha/settings ai_assistant/settings billing/settings emails/credentials sms/credentials]
    routes = keys.map do |key|
      AccessPoints::Descriptor.new(subject_type: "Route", subject_key: "admin/maintenance/platform/#{key}",
        subject_id: nil, actions: [:read], group_key: "admin.maintenance.platform", label: key.split("/").last.titleize)
    end
    route_catalog = double(groups: [{ key: "admin.maintenance.platform", label: "Platform", descriptors: routes }])
    role = build_stubbed(:role, customer: customer, locked_grants: false)
    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new(role: role, customer: customer, granted_keys: [], catalog: route_catalog))
    end
    rows = page.all("[data-grants-editor-target='row']")
    labels = rows.map { |row| row["data-display-label"] }
    expect(labels.uniq.size).to eq(5)
    expect(labels).to include("平台管理 — 验证码 — 设置", "平台管理 — 邮件 — 凭据", "平台管理 — 短信 — 凭据")
    rows.zip(routes).each do |row, descriptor|
      expect(row).to have_text(row["data-display-label"])
      expect(row["data-row-label"]).to eq(row["data-display-label"].downcase)
      expect(row).to have_css("input[data-grants-editor-subject-key-param='#{descriptor.subject_key}'][data-action-name='read']")
    end
    expect(page).not_to have_text(/Settings|Credentials|Platform|admin\//)
  end
end
