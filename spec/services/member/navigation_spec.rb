# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Navigation do
  let(:customer)        { create(:customer) }
  let(:payments_module) { find_or_create_feature_module!("payment", name: "Payments") }
  let(:user)            { create(:user, customer: customer) }

  describe ".items_for" do
    it "always returns the builtin home item" do
      keys = described_class.items_for(user).map(&:key)
      expect(keys).to include(:builtin_home)
    end

    it "hides builtin profile and security from the sidebar nav (the user menu exposes them)" do
      keys = described_class.items_for(user).map(&:key)
      expect(keys).not_to include(:builtin_profile, :builtin_security)
    end

    it "includes the payments item when the customer has the payments module enabled" do
      FeatureModules::CustomerAssignment.create!(
        customer: customer, feature_module: payments_module, status: :active
      )
      keys = described_class.items_for(user).map(&:key)
      expect(keys).to include(:payments)
    end

    it "excludes the payments item when the customer does not have the payments module enabled" do
      keys = described_class.items_for(user).map(&:key)
      expect(keys).not_to include(:payments)
    end

    it "returns Item objects with label, path, and icon populated" do
      home = described_class.items_for(user).find { |i| i.key == :builtin_home }
      expect(home.label).to eq("Home")
      expect(home.path_for(customer)).to eq("/#{customer.id}/member")
      expect(home.icon).to eq(:home)
    end

    describe "page links" do
      let!(:page) { create(:page, :launched, :for_member, customer: customer, name: "Enroll") }

      def enable_page_link!(for_customer:, for_page:)
        Member::SurfaceSetting.create!(
          customer: for_customer,
          surface_key: "page_#{for_page.id}",
          source_key: "pages",
          enabled: true
        )
      end

      it "omits page links until an admin enables them" do
        expect(described_class.items_for(user).map(&:key)).not_to include(:"page_#{page.id}")
      end

      it "builds /:cid/member/pages/<id> after an admin enables the link" do
        enable_page_link!(for_customer: customer, for_page: page)

        item = described_class.items_for(user).find { |i| i.key == :"page_#{page.id}" }
        expect(item).to be_present
        expect(item.label).to eq("Enroll")
        expect(item.path_for(customer)).to eq("/#{customer.id}/member/pages/#{page.id}")
      end

      it "never shows this tenant's page link to another tenant's member" do
        enable_page_link!(for_customer: customer, for_page: page)
        other_user = create(:user, customer: create(:customer))

        expect(described_class.items_for(other_user).map(&:key)).not_to include(:"page_#{page.id}")
      end
    end
  end
end

