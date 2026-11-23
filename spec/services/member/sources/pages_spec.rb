# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Sources::Pages do
  let_it_be(:customer) { create(:customer) }

  describe "metadata" do
    it_behaves_like "member source metadata", key: :pages, editable: true, position: 30

    it { expect(described_class.name).to eq("Pages") }
    it { expect(described_class.description).to eq("Launched pages members can open.") }
  end

  describe "#surfaces" do
    subject(:surfaces) { described_class.new(customer: customer).surfaces }

    def keys
      surfaces.map(&:key)
    end

    it "lists launched tenant and shared pages with member in the set" do
      tenant = create(:page, :launched, :for_member, customer: customer, name: "Enroll")
      shared = create(:page, :shared, :launched, :member_only, name: "Shared Enroll")

      expect(keys).to include(:"page_#{tenant.id}", :"page_#{shared.id}")
    end

    it "builds one BuiltinSurface per page with key page_<id>, label, path_seg, and default_enabled false" do
      page = create(:page, :launched, :for_member, customer: customer, name: "Enroll in course")
      surface = surfaces.find { |item| item.key == :"page_#{page.id}" }

      expect(surface).to be_a(Member::Sources::BuiltinSurface)
      expect(surface.label).to eq("Enroll in course")
      expect(surface.icon).to eq(:document_text)
      expect(surface.path_seg).to eq("pages/#{page.id}")
      expect(surface.default_enabled?).to be(false)
    end

    it "skips offline, trashed, admin-only, and public-only pages" do
      offline = create(:page, :for_member, customer: customer, name: "Draft")
      taken_offline = create(:page, :launched, :for_member, customer: customer, name: "Taken offline")
      taken_offline.take_offline!
      trashed = create(:page, :launched, :for_member, customer: customer, name: "Trashed")
      trashed.soft_delete
      admin_only = create(:page, :launched, customer: customer, name: "Admin only")
      public_only = create(:page, :launched, :public_only, customer: customer, name: "Public only")
      kept = create(:page, :launched, :for_member, customer: customer, name: "Kept")

      expect(keys).to include(:"page_#{kept.id}")
      expect(keys).not_to include(
        :"page_#{offline.id}",
        :"page_#{taken_offline.id}",
        :"page_#{trashed.id}",
        :"page_#{admin_only.id}",
        :"page_#{public_only.id}"
      )
    end

    it "lists only the resolver's choice when a tenant page and a shared page share an action key" do
      shared = create(:page, :shared, :launched, :member_only, name: "Shared Enroll", action_key: "enroll")
      tenant = create(:page, :launched, :member_only, customer: customer, name: "Tenant Enroll", action_key: "enroll")
      chosen = ::Pages::ActionResolver.page_for(
        customer_id: customer.id, action_key: "enroll", audience: "member"
      )

      expect(chosen).to eq(tenant)
      expect(keys).to include(:"page_#{tenant.id}")
      expect(keys).not_to include(:"page_#{shared.id}")
    end

    it "ignores another tenant's launched member page" do
      foreign = create(:page, :launched, :for_member, customer: create(:customer), name: "Foreign")

      expect(keys).not_to include(:"page_#{foreign.id}")
    end
  end
end
