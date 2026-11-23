# frozen_string_literal: true

require "rails_helper"

RSpec.describe MaintenanceContributor do
  let(:customer) { Customer.create!(id: 12345678, name: "T", industry: "technology") }
  let(:regular_user) { create(:user, customer: customer, role: :admin) }
  let(:context) do
    DashboardContext.new(
      current_user: regular_user,
      current_customer: customer,
      current_menu_item: :maintenance,
      request_path: "/"
    )
  end

  def contribute(ctx)
    described_class.new(ctx).contribute
  end

  describe "for regular customers" do
    it "emits standard items for admin users without flowcharts" do
      nodes = contribute(context)
      expect(nodes.map(&:label)).to eq([
        "Customer Profile", "Constants", "Modules", "Entities", "Pages", "Page shortcuts"
      ])
      expect(nodes.map(&:label)).not_to include("Flowcharts")
      expect(nodes.reject(&:section_root)).to all(have_attributes(menu_item: :maintenance))
    end

    it "points each leaf at the correct URL" do
      nodes = contribute(context)
      paths = nodes.map(&:path)
      expect(paths).to eq([
        "/#{customer.id}/admin/maintenance/customer_profile",
        "/#{customer.id}/admin/maintenance/constants",
        "/#{customer.id}/admin/maintenance/modules",
        "/#{customer.id}/admin/maintenance/entities",
        "/#{customer.id}/admin/maintenance/pages",
        "/#{customer.id}/admin/maintenance/page_shortcuts"
      ])
    end

    it "places Customer Profile at the top of the sidebar" do
      nodes = contribute(context)
      expect(nodes.first.label).to eq("Customer Profile")
      expect(nodes.first.key).to eq("maintenance.customer_profile")
    end

    it "includes Flowcharts when the actor is the platform owner" do
      nodes = contribute(
        DashboardContext.new(
          current_user: find_or_create_platform_owner,
          current_customer: customer,
          current_menu_item: :maintenance,
          request_path: "/"
        )
      )
      expect(nodes.map(&:label)).to eq([
        "Customer Profile", "Constants", "Modules", "Entities", "Flowcharts", "Pages", "Page shortcuts"
      ])
      expect(nodes.map(&:path)).to include("/#{customer.id}/admin/maintenance/flowcharts")
      expect(nodes.map(&:key)).not_to include("maintenance.customer_hostnames")
    end
  end

  describe "for platform customer owner (81721200)" do
    let(:platform_customer) { ensure_platform_customer }
    let(:platform_owner_user) { find_or_create_platform_owner }
    let(:platform_context) do
      DashboardContext.new(
        current_user: platform_owner_user,
        current_customer: platform_customer,
        current_menu_item: :maintenance,
        request_path: "/"
      )
    end

    it "nests Shared Resources under the Platform section" do
      nodes = contribute(platform_context)
      labels = nodes.map(&:label)
      expect(labels).to include("Platform", "Shared Resources")

      platform_index = labels.index("Platform")
      shared_index = labels.index("Shared Resources")
      expect(shared_index).to be > platform_index

      shared_group = nodes.find { |n| n.label == "Shared Resources" }
      expect(shared_group.section_root).to be false
      expect(shared_group.children.map(&:label)).to eq(["Constants", "Entities", "Flowcharts", "Pages"])

      constants_node = shared_group.children.find { |n| n.key == "maintenance.shared_constants" }
      expect(constants_node.path).to eq("/#{platform_customer.id}/admin/maintenance/platform/constants")
    end

    it "does not surface SMS credentials/templates as standalone sidebar leaves" do
      nodes = contribute(platform_context)
      labels = nodes.map(&:label)
      expect(labels).not_to include("SMS Credentials", "SMS Templates")
    end

    it "adds Platform section header" do
      nodes = contribute(platform_context)
      platform_section = nodes.find { |n| n.label == "Platform" }
      expect(platform_section).to be_present
      expect(platform_section.section_root).to be true
    end

    it "keeps Customers as the sole hostname management destination in both locales" do
      nodes = contribute(platform_context)
      expect(nodes.map(&:key)).not_to include("maintenance.customer_hostnames")
      expect(nodes.map(&:label)).not_to include("Customer hostnames")
      expect(nodes.count { |node| node.key == "maintenance.customers" }).to eq(1)

      nodes = I18n.with_locale(:"zh-CN") { contribute(platform_context) }
      expect(nodes.find { |node| node.key == "maintenance.customers" }.label).to eq("客户")
      expect(nodes.map(&:key)).not_to include("maintenance.customer_hostnames")
      expect(nodes.map(&:label)).not_to include("客户主机名")
    end

    it "links to correct platform URLs" do
      nodes = contribute(platform_context)
      customers_node = nodes.find { |n| n.label == "Customers" }
      announcements_node = nodes.find { |n| n.label == "Announcements" }
      support_tickets_node = nodes.find { |n| n.label == "Support tickets" }
      module_settings_node = nodes.find { |n| n.label == "Module Settings" }
      templates_node = nodes.find { |n| n.label == "Industry Templates" }
      generators_node = nodes.find { |n| n.label == "Code Generators" }

      expect(customers_node.path).to eq("/#{platform_customer.id}/admin/maintenance/platform/customers")
      expect(customers_node.match_prefix).to eq(customers_node.path)
      expect(nodes.none? { |node| node.path&.include?("/platform/customer_hostnames") }).to be true
      expect(announcements_node.path).to eq("/#{platform_customer.id}/admin/maintenance/platform/announcements")
      expect(support_tickets_node.path).to eq("/#{platform_customer.id}/admin/maintenance/platform/support_tickets")
      expect(nodes.map(&:label).index("Support tickets")).to eq(nodes.map(&:label).index("Announcements") + 1)
      expect(module_settings_node.path).to eq("/#{platform_customer.id}/admin/maintenance/platform/module_settings")
      expect(templates_node.path).to eq("/#{platform_customer.id}/admin/maintenance/platform/industry_templates")
      expect(generators_node.path).to eq("/#{platform_customer.id}/admin/maintenance/platform/code_generators")

      docs_node = nodes.find { |n| n.label == "Developer reference" }
      expect(docs_node.path).to eq("/#{platform_customer.id}/admin/maintenance/platform/developer_docs")
      expect(docs_node.match_prefix).to eq("/#{platform_customer.id}/admin/maintenance/platform/developer_docs")
    end
  end

  describe "for non-owner user on platform customer" do
    let(:platform_customer) { ensure_platform_customer }
    let(:platform_member) { create(:user, customer: platform_customer, role: :member) }
    let(:member_context) do
      DashboardContext.new(
        current_user: platform_member,
        current_customer: platform_customer,
        current_menu_item: :maintenance,
        request_path: "/"
      )
    end

    it "does not include platform-only items" do
      nodes = contribute(member_context)
      labels = nodes.map(&:label)
      expect(labels).not_to include("Platform", "Customers", "Customer hostnames", "Announcements", "Support tickets", "Module Settings", "Industry Templates", "Code Generators", "Developer reference", "Shared Resources")
    end
  end
end
