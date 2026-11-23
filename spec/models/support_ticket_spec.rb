# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupportTicket, type: :model do
  it "exposes the locked status set" do
    expect(described_class::STATUSES).to eq(%w[open resolved])
  end

  it "is open by default from the factory" do
    request = create(:support_ticket)
    expect(request).to be_open
    expect(request).not_to be_resolved
  end

  describe ".inbox_visible" do
    let(:now) { Time.zone.parse("2026-08-31 12:00:00") }

    it "includes open tickets regardless of age" do
      old = create(:support_ticket, last_message_at: now - 30.days)
      expect(described_class.inbox_visible(now)).to include(old)
    end

    it "includes recently resolved tickets" do
      recent = create(:support_ticket, :resolved, last_message_at: now - 2.days)
      expect(described_class.inbox_visible(now)).to include(recent)
    end

    it "hides resolved tickets older than 7 days" do
      aged = create(:support_ticket, :resolved, last_message_at: now - 8.days)
      expect(described_class.inbox_visible(now)).not_to include(aged)
    end
  end

  describe "#unread_for?" do
    it "is unread for the owner when the requester has posted and the owner has not opened it" do
      request = create(:support_ticket, :with_message)
      owner = find_or_create_platform_owner
      expect(request.unread_for?(owner)).to be true
    end

    it "is read for the requester after they open the ticket" do
      request = create(:support_ticket, :with_message)
      SupportTicketRead.record!(support_ticket: request, user_id: request.user_id)
      expect(request.unread_for?(request.user)).to be false
    end

    it "becomes unread for the requester when the owner replies after the cursor" do
      request = create(:support_ticket, :with_message)
      SupportTicketRead.record!(support_ticket: request, user_id: request.user_id)
      travel 1.minute do
        create(:support_ticket_message, :from_owner, support_ticket: request, user: find_or_create_platform_owner, customer: request.customer)
      end
      request.reload
      expect(request.unread_for?(request.user)).to be true
    end
  end

  describe "#thread_messages" do
    it "returns messages in chronological order" do
      request = create(:support_ticket, :with_message)
      later = create(:support_ticket_message, :from_owner, support_ticket: request, user: find_or_create_platform_owner, customer: request.customer)
      later.update_column(:created_at, request.messages.first.created_at + 1.minute)

      expect(request.thread_messages.map(&:id)).to eq(request.messages.order(:created_at, :id).pluck(:id))
    end
  end
end
