# frozen_string_literal: true

require "rails_helper"

RSpec.describe Help::Activities::AddMessage do
  let(:request) { create(:support_ticket, :with_message) }
  let(:owner) { find_or_create_platform_owner }

  it "appends an owner reply and advances last_message_at" do
    prior = request.last_message_at
    travel 1.minute do
      result = described_class.call(
        request: request,
        user: owner,
        author_role: "owner",
        params: { body: "We are looking into this." }
      )

      expect(result.success?).to be true
      expect(result.model.author_role).to eq("owner")
      expect(request.reload.last_message_at).to be > prior
    end
  end

  it "attaches every image on a reply" do
    result = described_class.call(
      request: request,
      user: owner,
      author_role: "owner",
      params: { body: "Screenshots attached.", images: [ png_upload("one.png"), png_upload("two.png") ] }
    )

    expect(result.success?).to be true
    expect(result.model.images.count).to eq(2)
  end

  it "rejects replies on a resolved ticket" do
    request.update!(status: "resolved")
    result = described_class.call(
      request: request,
      user: owner,
      author_role: "owner",
      params: { body: "Too late." }
    )

    expect(result.success?).to be false
    expect(result.messages).to include(I18n.t("help.errors.resolved"))
  end

  it "rejects a stale open instance after resolution without creating messages, images or read cursors" do
    stale = SupportTicket.find(request.id)
    expect(stale).to be_open
    Help::Activities::Resolve.call(request: request)
    cursor_count = SupportTicketRead.count
    blob_count = ActiveStorage::Blob.count
    allow(Notifications::Stream).to receive(:broadcast_help!)
    result = nil

    expect do
      result = described_class.call(request: stale, user: owner, author_role: "owner",
        params: { body: "Too late", images: [png_upload("late.png")] })
    end.not_to change(SupportTicketMessage, :count)

    expect(result).not_to be_success
    expect(result.messages).to include(I18n.t("help.errors.resolved"))
    expect(ActiveStorage::Blob.count).to eq(blob_count)
    expect(SupportTicketRead.count).to eq(cursor_count)
    expect(request.reload).to be_resolved
    expect(Notifications::Stream).not_to have_received(:broadcast_help!)
  end
end
