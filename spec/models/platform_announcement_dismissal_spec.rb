# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlatformAnnouncementDismissal do
  let(:customer)     { create(:customer) }
  let(:admin)        { create(:user, :admin, customer: customer) }
  let(:announcement) { create(:platform_announcement, :published, :all_customers) }

  describe ".record!" do
    it "persists the acknowledgement" do
      described_class.record!(announcement: announcement, user_id: admin.id, customer_id: customer.id)

      expect(described_class.count).to eq(1)
      expect(described_class.first.announcement).to eq(announcement)
    end

    it "is idempotent for the same user, customer and announcement" do
      2.times do
        described_class.record!(announcement: announcement, user_id: admin.id, customer_id: customer.id)
      end

      expect(described_class.count).to eq(1)
    end

    it "records the platform owner separately per tenant context" do
      other = create(:customer)
      described_class.record!(announcement: announcement, user_id: admin.id, customer_id: customer.id)
      described_class.record!(announcement: announcement, user_id: admin.id, customer_id: other.id)

      expect(described_class.count).to eq(2)
    end
  end

  describe ".announcement_ids_for" do
    it "returns only the ids this user dismissed in this tenant" do
      other_admin = create(:user, :admin, customer: customer)
      described_class.record!(announcement: announcement, user_id: admin.id, customer_id: customer.id)

      expect(described_class.announcement_ids_for(user_id: admin.id, customer_id: customer.id))
        .to eq([ announcement.id ])
      expect(described_class.announcement_ids_for(user_id: other_admin.id, customer_id: customer.id))
        .to eq([])
    end

    it "returns an empty list without a user or customer" do
      expect(described_class.announcement_ids_for(user_id: nil, customer_id: customer.id)).to eq([])
      expect(described_class.announcement_ids_for(user_id: admin.id, customer_id: nil)).to eq([])
    end
  end

  it "is removed when a never-live draft is destroyed" do
    draft = create(:platform_announcement, :draft)
    described_class.record!(announcement: draft, user_id: admin.id, customer_id: customer.id)

    draft.destroy!

    expect(described_class.count).to eq(0)
  end

  it "is kept when a live announcement is discarded" do
    described_class.record!(announcement: announcement, user_id: admin.id, customer_id: customer.id)

    announcement.discard_or_destroy!

    expect(described_class.count).to eq(1)
    expect(announcement.reload.deleted_at).to be_present
  end
end
