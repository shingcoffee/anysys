# frozen_string_literal: true

require "rails_helper"

RSpec.describe HelpMessageBubbleComponent, type: :component do
  let(:request) { create(:support_ticket, :with_message) }
  let(:message) { request.messages.first }

  it "aligns a requester message to the left with a visible author and timestamp" do
    owner = find_or_create_platform_owner
    render_inline(described_class.new(message: message, viewer: owner))

    expect(page).to have_text("Need help with this screen.")
    expect(page).to have_css("article[data-side='theirs'].items-start")
    expect(page).to have_text(request.user.display_name)
    expect(page).to have_css("time[datetime='#{message.created_at.iso8601}']")
    expect(page).to have_text(I18n.l(message.created_at, format: :short))
  end

  it "aligns the viewer's own message to the right with a visible You label" do
    render_inline(described_class.new(message: message, viewer: request.user))

    expect(page).to have_css("article[data-side='mine'].items-end")
    expect(page).to have_text("You")
    expect(page).to have_css("time[datetime]")
  end

  it "labels an owner reply as Platform for the requester" do
    owner = find_or_create_platform_owner
    reply = create(:support_ticket_message, :from_owner, support_ticket: request, user: owner, customer: request.customer, body: "Looking into it.")
    render_inline(described_class.new(message: reply, viewer: request.user))

    expect(page).to have_css("article[data-side='theirs']")
    expect(page).to have_text("Looking into it.")
    expect(page).to have_text(I18n.t("chrome.help_menu.thread.platform"))
  end
end
