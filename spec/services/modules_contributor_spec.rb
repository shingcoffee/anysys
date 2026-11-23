# frozen_string_literal: true

require "rails_helper"

RSpec.describe ModulesContributor do
  let(:customer) { Customer.create!(id: 12345678, name: "T", industry: "technology") }
  let(:context)  { DashboardContext.new(current_user: nil, current_customer: customer, current_menu_item: :modules, request_path: "/") }

  def contribute
    described_class.new(context).contribute
  end

  it "emits only nodes with menu_item: :modules" do
    nodes = contribute
    nodes.each do |node|
      expect(node.menu_item).to eq(:modules)
    end
    nodes.flat_map(&:children).each do |child|
      expect(child.menu_item).to eq(:modules)
    end
  end

  it "leads with an Overview link back to the hub" do
    first = contribute.first
    expect(first.key).to eq("modules.overview")
    expect(first.path).to eq("/#{customer.id}/admin/modules")
    expect(first.icon).to be_present
  end

  it "groups modules under the hub's category headings and puts future modules last" do
    %w[ai_assistant captcha website sms email payment authentication].each { |key| enable_module!(key, customer) }
    enable_module!("future", customer, name: "A Future Module")

    expect(contribute.map(&:key)).to eq(%w[
      modules.overview
      modules.category.records modules.authentication modules.website
      modules.category.communication modules.payment modules.email modules.sms
      modules.category.growth modules.captcha modules.ai_assistant
      modules.category.other modules.future
    ])
  end

  it "labels each category heading and tints each module group by its key" do
    enable_module!("email", customer)
    heading = contribute.find { |node| node.key == "modules.category.communication" }

    expect(heading).to be_category
    expect(heading).not_to be_link
    expect(heading.label).to eq("Communication")
    expect(I18n.with_locale(:"zh-CN") { contribute.find { |node| node.key == heading.key }.label }).to eq("沟通触达")
    expect(contribute.find { |node| node.key == "modules.email" }.tone).to eq("email")
  end

  it "omits headings for categories without enabled modules" do
    enable_module!("email", customer)

    keys = contribute.select(&:category?).map(&:key)
    expect(keys).to include("modules.category.communication")
    expect(keys).not_to include("modules.category.growth", "modules.category.other")
  end

  it "never links Manage Modules in the sidebar — enable/disable lives only under Maintenance / Modules" do
    owner = Authentication::User.new
    allow(owner).to receive(:platform_owner?).and_return(true)
    owner_context = DashboardContext.new(current_user: owner, current_customer: customer, current_menu_item: :modules, request_path: "/")

    keys = described_class.new(owner_context).contribute.map(&:key)
    expect(keys).not_to include("modules.manage")
    paths = described_class.new(owner_context).contribute.map(&:path)
    expect(paths).not_to include("/#{customer.id}/admin/maintenance/modules")
  end

  it "groups each enabled module's record entries under an iconed section" do
    enable_module!("email", customer)
    groups = contribute.select(&:section_root)
    email = groups.find { |g| g.key == "modules.email" }
    expect(email).to be_present
    expect(email.icon).to eq(Admin::Maintenance::Platform::ModuleSettingsHelper::MODULE_ICON_PATHS["email"])
    expect(email.description).to be_present
    labels = email.children.map(&:label)
    expect(email.children.first.key).to eq("modules.email.howto")
    expect(email.children.first.path).to eq("/#{customer.id}/admin/modules/email/howto")
    expect(labels).to include(I18n.t("feature_modules.email.entries.send_activities"))
  end

  it "keeps module settings pages out of the Modules tab — they live under Settings" do
    enable_module!("email", customer)
    email = contribute.find { |g| g.key == "modules.email" }
    keys = email.children.map(&:key)
    expect(keys).not_to include(a_string_including("daily_cap"))
    expect(keys).not_to include(a_string_including("template_tokens"))
  end

  it "shows guides for enabled settings-only modules without record entries" do
    %w[captcha ai_assistant].each { |key| enable_module!(key, customer) }

    %w[captcha ai_assistant].each do |key|
      group = contribute.find { |node| node.key == "modules.#{key}" }
      expect(group.children.map(&:key)).to eq(["modules.#{key}.howto"])
    end
  end
end
