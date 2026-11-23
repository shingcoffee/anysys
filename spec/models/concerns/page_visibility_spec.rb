# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageVisibility do
  let(:customer) { create(:customer) }

  def ids(*pages)
    Page.where(id: pages.map(&:id))
  end

  describe "#visible_to?" do
    it "is set membership: a public-only page is not visible to members or admins" do
      page = build(:page, :public_only, customer: customer)

      expect(page.visible_to?("public")).to be(true)
      expect(page.visible_to?("member")).to be(false)
      expect(page.visible_to?(:admin)).to be(false)
    end

    it "returns false for an unknown audience" do
      page = build(:page, :for_member, :for_public, customer: customer)

      expect(page.visible_to?(:unknown)).to be(false)
      expect(page.visible_to?("ghost")).to be(false)
    end
  end

  describe "#visible_audiences" do
    it "returns enabled audiences in admin, member, public order" do
      page = build(:page, customer: customer, audience_admin: false, audience_member: true, audience_public: true)

      expect(page.visible_audiences).to eq(%w[member public])
    end

    it "returns an empty list when no audience is selected" do
      page = build(:page, customer: customer, audience_admin: false, audience_member: false, audience_public: false)

      expect(page.visible_audiences).to eq([])
    end

    it "assigns the boolean columns from a list" do
      page = build(:page, customer: customer)
      page.visible_audiences = %w[public member]

      expect(page.audience_admin).to be(false)
      expect(page.audience_member).to be(true)
      expect(page.audience_public).to be(true)
      expect(page.visible_audiences).to eq(%w[member public])
    end
  end

  describe ".for_audience" do
    it "returns only pages that include the audience" do
      admin_page = create(:page, customer: customer)
      member_page = create(:page, :member_only, customer: customer)
      public_page = create(:page, :public_only, customer: customer)

      expect(ids(admin_page, member_page, public_page).for_audience("admin")).to contain_exactly(admin_page)
      expect(ids(admin_page, member_page, public_page).for_audience("member")).to contain_exactly(member_page)
      expect(ids(admin_page, member_page, public_page).for_audience("public")).to contain_exactly(public_page)
    end

    it "returns none for an unknown audience" do
      create(:page, :for_public, customer: customer)

      expect(Page.for_audience("ghost")).to be_empty
      expect(Page.for_audience(nil)).to be_empty
    end
  end
end
