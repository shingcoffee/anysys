# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::ActionResolver do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  around { |example| Current.set(customer: customer) { example.run } }

  def live_page(owner = customer, **attrs)
    create(:page, :launched, :member_only, customer: owner, action_key: "enroll", **attrs)
  end

  describe ".page_for" do
    it "returns the tenant page when a shared page shares the key and audience" do
      shared = create(:page, :shared, :launched, :member_only, action_key: "enroll")
      tenant = live_page

      expect(described_class.page_for(customer_id: customer.id, action_key: "enroll", audience: "member")).to eq(tenant)
      expect(described_class.page_for(customer_id: customer.id, action_key: "enroll", audience: "member")).not_to eq(shared)
    end

    it "falls back to the shared page when the tenant page is offline or trashed" do
      shared = create(:page, :shared, :launched, :member_only, action_key: "enroll")
      tenant = live_page

      tenant.take_offline!
      expect(described_class.page_for(customer_id: customer.id, action_key: "enroll", audience: "member")).to eq(shared)

      tenant.update_columns(launched: true, status: Page.statuses[:inactive])
      expect(described_class.page_for(customer_id: customer.id, action_key: "enroll", audience: "member")).to eq(shared)
    end

    it "ignores another tenant's page" do
      live_page(other_customer)
      shared = create(:page, :shared, :launched, :member_only, action_key: "enroll")

      expect(described_class.page_for(customer_id: customer.id, action_key: "enroll", audience: "member")).to eq(shared)
    end

    it "returns nil when the action key is blank" do
      live_page

      expect(described_class.page_for(customer_id: customer.id, action_key: nil, audience: "member")).to be_nil
      expect(described_class.page_for(customer_id: customer.id, action_key: "", audience: "member")).to be_nil
    end
  end

  describe ".pages_for" do
    it "resolves several keys at once, as page_for does for each" do
      shared = create(:page, :shared, :launched, :member_only, action_key: "enroll")
      tenant = live_page
      renew_shared = create(:page, :shared, :launched, :member_only, action_key: "renew")
      live_page(other_customer, action_key: "renew")
      create(:page, :launched, :public_only, customer: customer, action_key: "apply")

      expect(described_class.pages_for(customer_id: customer.id, action_keys: %w[enroll renew apply], audience: "member"))
        .to eq("enroll" => tenant, "renew" => renew_shared)
      expect(described_class.pages_for(customer_id: nil, action_keys: ["enroll", nil], audience: "member"))
        .to eq("enroll" => shared)
    end

    it "returns nothing without keys or for an unknown audience" do
      live_page

      expect(described_class.pages_for(customer_id: customer.id, action_keys: [nil, ""], audience: "member")).to eq({})
      expect(described_class.pages_for(customer_id: customer.id, action_keys: ["enroll"], audience: "staff")).to eq({})
    end
  end

  describe ".counterpart" do
    it "finds the member page of a public page's action" do
      public_page = create(:page, :launched, :public_only, customer: customer, action_key: "enroll")
      member_page = live_page

      expect(described_class.counterpart(page: public_page, audience: "member")).to eq(member_page)
      expect(described_class.counterpart(page: member_page, audience: "member")).to be_nil
    end

    it "sends a shared page to the visited tenant's page for the same audience" do
      shared = create(:page, :shared, :launched, :member_only, action_key: "enroll")
      tenant = live_page

      expect(described_class.counterpart(page: shared, audience: "member", customer_id: customer.id)).to eq(tenant)
      expect(described_class.counterpart(page: tenant, audience: "member", customer_id: customer.id)).to be_nil
      expect(described_class.counterpart(page: shared, audience: "member", customer_id: other_customer.id)).to be_nil
    end

    it "returns nil when the page has no action key" do
      page = create(:page, :launched, :public_only, customer: customer)

      expect(described_class.counterpart(page: page, audience: "member")).to be_nil
    end
  end

  describe ".siblings" do
    it "returns other active pages in the same action and owner, launched or not" do
      public_page = create(:page, :launched, :public_only, customer: customer, action_key: "enroll")
      member_page = live_page
      draft = create(:page, :member_only, customer: customer, action_key: "enroll")
      create(:page, :launched, :member_only, customer: other_customer, action_key: "enroll")
      create(:page, :shared, :launched, :member_only, action_key: "enroll")

      expect(described_class.siblings(public_page)).to contain_exactly(member_page, draft)
    end

    it "returns none when the page has no action key" do
      page = create(:page, customer: customer)

      expect(described_class.siblings(page)).to be_empty
    end
  end
end
