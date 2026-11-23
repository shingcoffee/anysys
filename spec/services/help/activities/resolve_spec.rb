# frozen_string_literal: true

require "rails_helper"

RSpec.describe Help::Activities::Resolve do
  it "marks an open ticket resolved" do
    request = create(:support_ticket)
    result = described_class.call(request: request)

    expect(result.success?).to be true
    expect(result.model.reload).to be_resolved
  end

  it "rejects a ticket that is already resolved" do
    request = create(:support_ticket, :resolved)
    result = described_class.call(request: request)

    expect(result.success?).to be false
    expect(result.messages).to include(I18n.t("help.errors.resolved"))
  end

  it "reloads an open stale instance and rejects a second resolution" do
    request = create(:support_ticket)
    stale = SupportTicket.find(request.id)
    described_class.call(request: request)
    timestamp = request.reload.updated_at

    result = described_class.call(request: stale)

    expect(result).not_to be_success
    expect(result.messages).to include(I18n.t("help.errors.resolved"))
    expect(stale).to be_resolved
    expect(request.reload.updated_at).to eq(timestamp)
  end
end
