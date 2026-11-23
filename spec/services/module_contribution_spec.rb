# frozen_string_literal: true

require "rails_helper"

RSpec.describe ModuleContribution do
  subject(:contribution) do
    described_class.new(label: "Payments", entry_key: :payments)
  end

  def node(menu_item)
    contribution.to_sidebar_node(menu_item: menu_item, module_key: :payment, customer_id: 12345678)
  end

  it "produces a SidebarNode carrying the requested menu_item" do
    expect(node(:modules).menu_item).to eq(:modules)
  end

  it "defaults path correctly for :modules menu_item" do
    expect(node(:modules).path).to eq("/12345678/admin/modules/payments/entries/payments")
    expect(node(:modules).match_prefix).to eq("/12345678/admin/modules/payments/entries/payments")
  end

  it "defaults path correctly for :settings menu_item" do
    expect(node(:settings).path).to eq("/12345678/admin/settings/modules/payments/payments")
  end

  it "renders nested children as SidebarNode children" do
    parent = described_class.new(
      label: "Campaigns",
      entry_key: "campaigns",
      children: [
        described_class.new(label: "All Campaigns", entry_key: "all_campaigns"),
        described_class.new(label: "Lists", entry_key: "lists")
      ]
    )

    sidebar_node = parent.to_sidebar_node(menu_item: :modules, module_key: :email, customer_id: 12345678)

    expect(sidebar_node.path).to be_nil
    expect(sidebar_node.children.size).to eq(2)
    expect(sidebar_node.children.map(&:label)).to eq(["All Campaigns", "Lists"])
    expect(sidebar_node.children.map(&:key)).to eq(["modules.email.all_campaigns", "modules.email.lists"])
  end

  describe "#href_for" do
    it "resolves a callable path" do
      contribution = described_class.new(
        label: "Users",
        entry_key: "users",
        path: ->(customer_id) { "/#{customer_id}/admin/modules/authentication/users" }
      )

      expect(contribution.href_for(customer_id: 12, menu_item: :modules, module_key: "authentication"))
        .to eq("/12/admin/modules/authentication/users")
    end

    it "uses the modules default path when path is omitted" do
      contribution = described_class.new(label: "Payments", entry_key: :payments)

      expect(contribution.href_for(customer_id: 12345678, menu_item: :modules, module_key: :payment))
        .to eq("/12345678/admin/modules/payments/entries/payments")
    end

    it "uses the settings default path when path is omitted" do
      contribution = described_class.new(label: "Daily cap", entry_key: "daily_cap")

      expect(contribution.href_for(customer_id: 1, menu_item: :settings, module_key: "sms"))
        .to eq("/1/admin/settings/modules/sms/daily_cap")
    end
  end

  it "passes match_prefix through to the resulting SidebarNode" do
    grouped = described_class.new(label: "Content", entry_key: "content", path: "/templates",
                                   match_prefix: ["/templates", "/assets"])

    sidebar_node = grouped.to_sidebar_node(menu_item: :modules, module_key: :email, customer_id: 1)

    expect(sidebar_node.match_prefix).to eq(["/templates", "/assets"])
  end
end
