# frozen_string_literal: true

require "rails_helper"

RSpec.describe MenuRegistry do
  let(:member) { double(owner?: false, admin_or_owner?: false) }
  let(:admin)  { double(owner?: false, admin_or_owner?: true) }
  let(:owner)  { double(owner?: true, admin_or_owner?: true, platform_owner?: true) }

  describe ".for" do
    it "returns the five universal items for members" do
      keys = described_class.for(member).map(&:key)
      expect(keys).to eq([:home, :assistant, :entities, :modules, :settings])
    end

    it "returns [] when user is nil" do
      expect(described_class.for(nil)).to eq([])
    end
  end

  describe ".item" do
    it "looks up by key" do
      expect(described_class.item(:home).label).to eq("Home")
    end

    it "returns nil for unknown key" do
      expect(described_class.item(:unknown)).to be_nil
    end
  end

  describe "Maintenance navigation" do
    it "includes :maintenance for the platform owner" do
      keys = described_class.for(owner).map(&:key)
      expect(keys).to include(:maintenance)
    end

    it "omits :maintenance for tenant admins" do
      keys = described_class.for(admin).map(&:key)
      expect(keys).not_to include(:maintenance)
    end

    it "omits :maintenance for an admin of the platform customer" do
      platform_admin = double(admin_or_owner?: true, platform_owner?: false)
      expect(described_class.for(platform_admin).map(&:key)).not_to include(:maintenance)
    end

    it "omits :maintenance for members" do
      keys = described_class.for(member).map(&:key)
      expect(keys).not_to include(:maintenance)
    end
  end

  describe "module shortcuts" do
    let(:customer) { create(:customer) }

    it "places tenant-scoped shortcuts after AI Assistant and filters unavailable destinations" do
      enable_module!("authentication", customer)
      enable_module!("email", customer)

      items = described_class.for(admin, customer: customer)
      expect(items.map(&:key).first(5)).to eq(%i[home assistant users communication entities])
      expect(items.map(&:key)).not_to include(:payments)
      expect(items.find { |item| item.key == :users }.path_for(customer))
        .to eq("/#{customer.id}/admin/modules/authentication/users")
      expect(items.find { |item| item.key == :communication }.children.map(&:key)).to eq([:email])
    end

    it "includes both communication destinations and Payments when enabled" do
      %w[authentication payment email sms].each { |key| enable_module!(key, customer) }

      items = described_class.for(admin, customer: customer)
      expect(items.map(&:key).first(5)).to eq(%i[home assistant users payments communication])
      expect(items.find { |item| item.key == :payments }.path_for(customer))
        .to eq("/#{customer.id}/admin/modules/payments/transactions")
      expect(items.find { |item| item.key == :communication }.children.map { |child| child.path_for(customer) }).to eq([
        "/#{customer.id}/admin/modules/emails/send_activities",
        "/#{customer.id}/admin/modules/sms/campaigns"
      ])
      expect(described_class.for(member, customer: customer).map(&:key)).not_to include(:users, :payments, :communication)
    end

    it "checks the URL customer instead of the owner's own tenant" do
      enable_module!("email", customer)
      other_customer = create(:customer)

      expect(described_class.for(owner, customer: other_customer).map(&:key)).not_to include(:communication)
      expect(described_class.for(owner, customer: customer).map(&:key)).to include(:communication)
    end
  end

  describe "Website navigation" do
    let(:customer) { create(:customer) }

    it "keeps forms in Domains and shows Website only for tenants with Website enabled" do
      enable_module!("website", customer)
      other_customer = create(:customer)

      website = described_class.for(owner, customer: customer).find { |item| item.key == :website_pages }
      expect(website).not_to be_dropdown
      expect(website.label).to eq("Website")
      expect(website.path_for(customer)).to eq("/#{customer.id}/admin/modules/website")
      expect(described_class.for(owner, customer: other_customer).map(&:key)).not_to include(:website_pages, :pages)
      expect(described_class.item(:entities).path_for(customer)).to eq("/#{customer.id}/admin/domains")
    end
  end
end
