# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageShortcuts::TargetEligibility do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:website) { create(:website, :published, customer: customer) }
  let(:website_page) { create(:website_page, :published, website: website, customer: customer, slug: "pricing") }
  let(:page) { create(:page, :for_member, :for_public, customer: customer, launched: true) }
  let(:shared_page) { create(:page, :shared, :for_member, :for_public, launched: true) }
  let(:website_module) { enable_module!("website", customer, name: "Website") }

  before { website_module }
  after { Current.reset }

  it "requires both website ownership columns, module enablement and published site/page" do
    expect(described_class.eligible?(website_page, customer_id: customer.id)).to be(true)
    expect(described_class.eligible?(website_page, customer_id: other_customer.id)).to be(false)
    website_page.update!(customer_id: other_customer.id)
    expect(described_class.eligible?(website_page, customer_id: other_customer.id)).to be(false)
  end

  it "reads current database eligibility rather than a stale target object" do
    website_page.update!(published: false)
    expect(described_class.eligible?(website_page, customer_id: customer.id)).to be(false)
    website_page.update!(published: true)
    website.update!(published: false)
    expect(described_class.eligible?(website_page, customer_id: customer.id)).to be(false)
    website.update!(published: true)
    website_module.update!(status: :inactive)
    expect(described_class.eligible?(website_page, customer_id: customer.id)).to be(false)
    website_module.update!(status: :active)
    customer.customer_feature_modules.find_by!(feature_module: website_module).update!(status: :suspended)
    expect(described_class.eligible?(website_page, customer_id: customer.id)).to be(false)
  end

  it "allows launched public tenant/shared Pages only, without definition/Current reads" do
    mine = page
    shared = shared_page
    Current.customer = other_customer
    expect(Page).not_to receive(:accessible)
    expect_any_instance_of(Page).not_to receive(:reload_definition_from_head!)

    expect(described_class.eligible?(mine, customer_id: customer.id)).to be(true)
    expect(described_class.eligible?(mine, customer_id: other_customer.id)).to be(false)
    expect(described_class.eligible?(shared, customer_id: other_customer.id)).to be(true)
    expect(Current.customer).to eq(other_customer)
  end

  it "accepts a scoped shortcut identity without loading its target association" do
    mapping = PageShortcut.create!(customer_id: customer.id, path: "/join", target: shared_page)
    expect(mapping).not_to receive(:target)
    expect(described_class.eligible?(mapping, customer_id: customer.id)).to be(true)
    expect(described_class.eligible?(mapping, customer_id: other_customer.id)).to be(false)
  end

  it "allows a public-only page and rejects a member-only page" do
    public_only = create(:page, :public_only, :launched, customer: customer)
    member_only = create(:page, :member_only, :launched, customer: customer)

    expect(described_class.eligible?(public_only, customer_id: customer.id)).to be(true)
    expect(described_class.eligible?(member_only, customer_id: customer.id)).to be(false)
  end

  it "fails closed for private, unlaunched, inactive, missing and inactive-customer targets" do
    page.update!(audience_admin: true, audience_member: false, audience_public: false)
    expect(described_class.eligible?(page, customer_id: customer.id)).to be(false)
    page.update!(audience_member: true)
    expect(described_class.eligible?(page, customer_id: customer.id)).to be(false)
    page.update!(audience_public: true, launched: false)
    expect(described_class.eligible?(page, customer_id: customer.id)).to be(false)
    page.update!(launched: true, status: :inactive)
    expect(described_class.eligible?(page, customer_id: customer.id)).to be(false)
    expect(described_class.resolve(type: "Customer", id: customer.id, customer_id: customer.id)).to be_nil
    expect(described_class.resolve(type: "Page", id: "#{page.id}junk", customer_id: customer.id)).to be_nil
    expect(described_class.resolve(type: "Page", id: 999999999, customer_id: customer.id)).to be_nil
    customer.update!(status: :inactive)
    expect(described_class.eligible?(shared_page, customer_id: customer.id)).to be(false)
  end
end
