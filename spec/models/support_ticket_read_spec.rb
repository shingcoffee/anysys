# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupportTicketRead, type: :model do
  let(:request) { create(:support_ticket) }
  let(:admin) { request.user }

  describe ".record!" do
    it "persists last_read_at for the ticket's customer" do
      row = described_class.record!(support_ticket: request, user_id: admin.id)

      expect(row.customer_id).to eq(request.customer_id)
      expect(row.last_read_at).to be_present
    end

    it "updates last_read_at on a second call rather than inserting" do
      first = described_class.record!(support_ticket: request, user_id: admin.id)
      travel 1.minute do
        described_class.record!(support_ticket: request, user_id: admin.id)
      end

      expect(described_class.count).to eq(1)
      expect(described_class.first.last_read_at).to be > first.last_read_at
    end

    it "treats a unique-index conflict as an update of last_read_at" do
      existing = described_class.create!(
        support_ticket: request, user_id: admin.id, customer_id: request.customer_id, last_read_at: 1.hour.ago
      )
      colliding = described_class.new(support_ticket_id: request.id, user_id: admin.id)
      allow(described_class).to receive(:find_or_initialize_by).and_return(colliding)
      allow(colliding).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique.new("idx"))

      travel 1.minute do
        row = described_class.record!(support_ticket: request, user_id: admin.id)
        expect(row.id).to eq(existing.id)
        expect(row.last_read_at).to be > existing.last_read_at
      end
    end
  end
end
