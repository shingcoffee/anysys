# frozen_string_literal: true

require "rails_helper"

RSpec.describe SettingsContributor do
  let_it_be(:customer) { create(:customer) }
  let(:context) do
    DashboardContext.new(
      current_user: double(admin_or_owner?: true),
      current_customer: customer,
      current_menu_item: :settings,
      request_path: "/"
    )
  end

  before do
    FeatureModules::CustomerAssignment.where(customer: customer).destroy_all
    FeatureModules::Module.update_all(required: false)
  end

  def enable_module(key:, name:, configuration_schema: {}, settings_contributions: [])
    fm = enable_module!(key, customer, name: name)
    fm.update!(configuration_schema: configuration_schema.to_json, name: name)
    allow(fm.registration_class).to receive(:sidebar_contributions)
      .and_return(entries: [], settings: settings_contributions)
    fm
  end

  def module_nodes(nodes)
    nodes.select { |n| n.key.start_with?("settings.modules.") }
  end

  def keys(nodes)
    nodes.map(&:key)
  end

  it "starts with Overview and retains the shared settings sections" do
    nodes = described_class.new(context).contribute
    expect(keys(nodes)).to eq(%w[
      settings.overview
      settings.category.organization
      settings.section.members
      settings.member
      settings.section.billing
      settings.subscription
      settings.payment_methods
      settings.invoices
    ])
    overview = nodes.find { |n| n.key == "settings.overview" }
    expect(overview.path).to eq("/#{customer.id}/admin/settings")
    expect(overview.description).to eq("Browse every setting for this organization.")
  end

  it "always emits a tenant-wide Member node" do
    nodes = described_class.new(context).contribute
    member = nodes.find { |n| n.key == "settings.member" }
    expect(member).not_to be_nil
    expect(member.label).to eq("Member portal")
    expect(member.path).to eq("/#{customer.id}/admin/settings/member")
    expect(member.menu_item).to eq(:settings)
    expect(member.description).to eq("Choose what members see in their portal.")
  end

  it "flattens billing leaves under a section label rather than a collapsible parent" do
    nodes = described_class.new(context).contribute
    billing = nodes.find { |n| n.key == "settings.section.billing" }
    expect(billing.section_root).to be(true)
    expect(billing).not_to be_link
    expect(nodes.find { |n| n.key == "settings.subscription" }.path)
      .to eq("/#{customer.id}/admin/settings/billing/subscription")
    expect(nodes.find { |n| n.key == "settings.invoices" }.match_prefix)
      .to eq("/#{customer.id}/admin/settings/billing/invoices")
  end

  it "omits the Modules section when the customer has no enabled modules" do
    nodes = described_class.new(context).contribute
    expect(module_nodes(nodes)).to eq([])
    expect(nodes.map(&:key)).not_to include("settings.section.modules")
  end

  it "omits modules with empty settings contributions AND empty configuration_schema" do
    enable_module(key: "mod_a", name: "Mod A", configuration_schema: {}, settings_contributions: [])
    nodes = described_class.new(context).contribute
    expect(module_nodes(nodes)).to eq([])
  end

  it "links to configuration for a handoff-enabled module with no other settings" do
    fm = enable_module(key: "mod_a", name: "Mod A", configuration_schema: {}, settings_contributions: [])
    fm.update!(handoff_enabled: true)

    nodes = described_class.new(context).contribute
    expect(nodes.map(&:key)).to include("settings.section.mod_a", "settings.mod_a.return_url")
    expect(nodes.find { |node| node.key == "settings.mod_a.return_url" }.path)
      .to eq("/#{customer.id}/admin/settings/modules/mod_as/return_url")
  end

  it "adds a Return URL destination only for handoff-enabled modules with dedicated settings pages" do
    %w[payment captcha website].each { |key| enable_module!(key, customer) }
    payment = FeatureModules::Module.find_by!(key: "payment")
    payment.update!(handoff_enabled: true)
    nodes = described_class.new(context).contribute

    expect(nodes.find { |node| node.key == "settings.payment.return_url" }.path)
      .to eq("/#{customer.id}/admin/settings/modules/payments/return_url")
    expect(nodes.map(&:key)).not_to include("settings.captcha.return_url", "settings.website.return_url")
  end

  it "lists a module as a leaf when it has a configuration_schema but no settings contributions" do
    enable_module(
      key: "mod_b", name: "Mod B",
      configuration_schema: { "flag" => { "type" => "boolean" } },
      settings_contributions: []
    )
    nodes = described_class.new(context).contribute
    expect(module_nodes(nodes).map(&:label)).to eq(["Mod B"])
    expect(nodes.map(&:key)).to include("settings.section.mod_b")
    module_node = nodes.find { |n| n.key == "settings.modules.mod_b" }
    expect(module_node.children).to eq([])
    expect(module_node.path).to eq("/#{customer.id}/admin/settings/modules/mod_bs")
    expect(module_node.menu_item).to eq(:settings)
    expect(module_node.description).to eq("Configure Mod B for this organization.")
  end

  it "flattens future module destinations while preserving their permission IDs" do
    enable_module(
      key: "mod_c", name: "Mod C",
      configuration_schema: {},
      settings_contributions: [
        ModuleContribution.new(label: "Gateway", entry_key: "gateway")
      ]
    )
    nodes = described_class.new(context).contribute
    gateway = nodes.find { |n| n.key == "settings.mod_c.gateway" }
    expect(gateway.label).to eq("Gateway")
    expect(gateway.children).to be_empty
    expect(gateway.path).to eq("/#{customer.id}/admin/settings/modules/mod_cs/gateway")
    expect(gateway.description).to eq("Configure Mod C for this organization.")
    expect(gateway.icon).to eq(described_class::SETTING_ICON)
    expect(keys(nodes)).to include("settings.section.mod_c")
  end

  it "uses the known-module identity icon when the key is a platform module" do
    enable_module(
      key: "authentication", name: "User Authentication",
      configuration_schema: { "x" => {} }
    )
    nodes = described_class.new(context).contribute
    auth = nodes.find { |n| n.key == "settings.modules.authentication" }
    expect(auth.icon).to eq(
      Admin::Maintenance::Platform::ModuleSettingsHelper::MODULE_ICON_PATHS.fetch("authentication")
    )
    expect(auth.description).to eq("Configure account security preferences.")
    expect(auth.path).to eq("/#{customer.id}/admin/settings/modules/authentication")
    expect(auth.match_prefix).to be_nil
    expect(auth.match_paths).to eq([
      "/#{customer.id}/admin/settings/modules/authentication",
      "/#{customer.id}/admin/settings/modules/authentications"
    ])
  end

  it "orders modules by name" do
    enable_module(key: "mod_z", name: "Zeta", configuration_schema: { "x" => {} })
    enable_module(key: "mod_a", name: "Alpha", configuration_schema: { "x" => {} })
    nodes = described_class.new(context).contribute
    expect(module_nodes(nodes).map(&:label)).to eq(["Alpha", "Zeta"])
  end

  it "places unrecognized module settings after the built-in modules" do
    enable_module!("email", customer)
    enable_module(key: "future", name: "A Future Module", configuration_schema: { "flag" => { "type" => "boolean" } })

    expect(described_class.new(context).contribute.select(&:section_root).map(&:key)).to eq(%w[
      settings.section.email settings.section.future settings.section.members settings.section.billing
    ])
  end

  it "retains every registered destination under its own module section in navigation order" do
    %w[authentication captcha website ai_assistant email sms payment].each { |key| enable_module!(key, customer) }
    nodes = described_class.new(context).contribute
    expect(nodes.select { |node| node.section_root || node.category? }.map(&:key)).to eq(%w[
      settings.category.records settings.section.authentication settings.section.website
      settings.category.communication settings.section.payment settings.section.email settings.section.sms
      settings.category.growth settings.section.captcha settings.section.ai_assistant
      settings.category.organization settings.section.members settings.section.billing
    ])
    expect(nodes.find { |node| node.key == "settings.section.sms" }.tone).to eq("sms")
    expect(nodes.find { |node| node.key == "settings.section.billing" }.tone).to be_nil
    expect(nodes.select(&:link?).map(&:key)).to match_array(["settings.overview", *described_class::ITEMS.keys])
    expect(nodes.all? { |node| node.children.empty? }).to be(true)
    expect(nodes.find { |node| node.key == "settings.authentication.roles" }.permitted_by).to eq(:admin_or_owner?)
    expect(nodes.slice(nodes.index { |n| n.key == "settings.section.email" } + 1, 2).map(&:key)).to eq(
      %w[settings.email.daily_cap settings.email.template_tokens]
    )
  end

  it "omits disabled modules and modules assigned only to another customer" do
    fm = enable_module!("email", customer)
    FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: fm).update!(status: :suspended)
    enable_module!("payment", create(:customer))
    nodes = described_class.new(context).contribute
    expect(keys(nodes)).not_to include("settings.email.daily_cap", "settings.payment.merchant_accounts")
  end

  it "filters nested permission guards before flattening for catalog consumers" do
    enable_module(key: "future", name: "Future", settings_contributions: [
      ModuleContribution.new(label: "Hidden group", entry_key: "hidden", permitted_by: ->(_) { false }, children: [
        ModuleContribution.new(label: "Hidden child", entry_key: "child")
      ]),
      ModuleContribution.new(label: "Allowed", entry_key: "allowed"),
      ModuleContribution.new(label: "Denied", entry_key: "denied", permitted_by: ->(_) { false })
    ])
    nodes = described_class.new(context).contribute
    expect(keys(nodes)).to include("settings.future.allowed")
    expect(keys(nodes)).not_to include("settings.future.child", "settings.future.denied", "settings.future.hidden")
  end

  it "uses the approved Chinese names at call time with the same destinations" do
    contributor = described_class.new(context)
    english = contributor.contribute
    chinese = I18n.with_locale(:"zh-CN") { contributor.contribute }
    expect(chinese.map(&:path)).to eq(english.map(&:path))
    expect(chinese.find { |node| node.key == "settings.member" }.label).to eq("会员中心")
    expect(chinese.select(&:section_root).map(&:label)).to eq(["会员", "账单"])
    expect(chinese.select(&:category?).map(&:label)).to eq(["组织"])
  end

  it "selects exactly the task destination on deep pages and never double-highlights account security" do
    %w[authentication email payment captcha website ai_assistant sms].each { |key| enable_module!(key, customer) }
    nodes = described_class.new(context).contribute
    {
      "" => "settings.overview",
      "/modules/authentication" => "settings.modules.authentication",
      "/modules/authentications" => "settings.modules.authentication",
      "/modules/authentication/" => "settings.modules.authentication",
      "/modules/authentications/" => "settings.modules.authentication",
      "/modules/authentication?locale=zh-CN" => "settings.modules.authentication",
      "/modules/authentications/?locale=zh-CN" => "settings.modules.authentication",
      "/modules/authentication/sign_up" => "settings.authentication.sign_up",
      "/modules/authentication/forget_password" => "settings.authentication.forget_password",
      "/modules/authentication/roles/new" => "settings.authentication.roles",
      "/modules/authentication/roles/12/edit" => "settings.authentication.roles",
      "/modules/authentication/roles/12/grants" => "settings.authentication.roles",
      "/modules/authentication/user_role_assignments/12/edit" => "settings.authentication.user_role_assignments",
      "/modules/emails/template_tokens/12/edit" => "settings.email.template_tokens",
      "/modules/email" => "settings.email.daily_cap",
      "/modules/emails" => "settings.email.daily_cap",
      "/modules/emails/?locale=zh-CN" => "settings.email.daily_cap",
      "/modules/sms" => "settings.sms.daily_cap",
      "/modules/sms/daily_cap" => "settings.sms.daily_cap",
      "/modules/ai_assistants" => "settings.ai_assistant.status",
      "/modules/ai_assistant" => "settings.ai_assistant.status",
      "/modules/captcha/status" => "settings.captcha.status",
      "/modules/payments/merchant_accounts/12/edit" => "settings.payment.merchant_accounts",
      "/member/sources/entities/surfaces/profile" => "settings.member",
      "/billing/invoices/12" => "settings.invoices",
      "/billing/payment_methods/new" => "settings.payment_methods",
      "/modules/website" => "settings.website.site"
    }.each do |suffix, key|
      active = nodes.select do |node|
        SidebarNodeComponent.new(node: node, current_path: "/#{customer.id}/admin/settings#{suffix}").active?
      end
      expect(active.map(&:key)).to eq([key]), "incorrect selection for #{suffix}"
      expect(SidebarNodeComponent.selected_key(nodes, "/#{customer.id}/admin/settings#{suffix}")).to eq(key)
    end
  end

  it "retains a single exact-root item through sidebar permission filtering" do
    enable_module!("authentication", customer)
    tree = SidebarBuilder.build(context, menu_item: :settings)
    nodes = tree.nodes_for(:settings)
    expect(nodes.count { |node| node.key == "settings.modules.authentication" }).to eq(1)
    active = nodes.select do |node|
      SidebarNodeComponent.new(node: node, current_path: "/#{customer.id}/admin/settings/modules/authentications").active?
    end
    expect(active.map(&:key)).to eq(["settings.modules.authentication"])
  end
end
