# frozen_string_literal: true

require "rails_helper"

RSpec.describe HelpThreadComponent, type: :component do
  let(:request) { create(:support_ticket, :with_message) }
  let(:messages) { request.messages.to_a }

  it "renders the subject thread and a reply composer when open" do
    render_inline(
      described_class.new(
        support_ticket: request,
        messages: messages,
        viewer: request.user,
        reply_path: "/1/admin/support_tickets/#{request.id}/messages"
      )
    )

    expect(page).to have_text("Need help with this screen.")
    expect(page).to have_css("article[data-side='mine'].items-end")
    expect(page).to have_text("You")
    expect(page).to have_text("Conversation")
    expect(page).to have_css("[data-help-region='chat']")
    expect(page).to have_css("[data-help-region='details']")
    expect(page).to have_text("Ticket details")
    expect(page).not_to have_link(I18n.t("maint_platform.customers.index.act_as"))
    expect(page).to have_css("button[aria-label='#{I18n.t("chrome.help_menu.thread.send_reply")}']")
    expect(page).to have_css("form[action='/1/admin/support_tickets/#{request.id}/messages']")
    expect(page).to have_css("form[data-controller='help-attachments']")
    expect(page).to have_css("form[data-help-thread-target='form']")
    expect(page).to have_css("input#help-reply-files")
    expect(page).to have_css("[data-help-thread-target='thread'].overflow-y-auto")
    expect(page).to have_css("[data-controller='help-thread']")
    expect(page).to have_text(I18n.t("chrome.help_menu.thread.send_hint"))
  end

  it "hides the composer and shows the resolved note" do
    request.update!(status: "resolved")
    render_inline(
      described_class.new(
        support_ticket: request,
        messages: messages,
        viewer: request.user,
        reply_path: "/1/admin/support_tickets/#{request.id}/messages"
      )
    )

    expect(page).to have_text("This ticket is resolved.")
    expect(page).not_to have_css("button[aria-label='#{I18n.t("chrome.help_menu.thread.send_reply")}']")
  end

  it "renders the resolve action with a confirm for the owner view" do
    render_inline(
      described_class.new(
        support_ticket: request,
        messages: messages,
        viewer: request.user,
        reply_path: "/81721200/admin/maintenance/platform/support_tickets/#{request.id}/messages",
        resolve_path: "/81721200/admin/maintenance/platform/support_tickets/#{request.id}/resolution",
        owner_view: true
      )
    )

    expect(page).to have_button("Mark resolved")
    expect(page).to have_text("Ticket details")
    expect(page).to have_css("form[action$='/resolution'][data-turbo-confirm]")
    expect(page).to have_text(request.customer.name)
    expect(page).to have_text(request.customer_id.to_s)
    expect(page).to have_text(request.user.email)
    expect(page).to have_link(
      I18n.t("maint_platform.customers.index.act_as"),
      href: "/#{request.customer_id}/admin/dashboard"
    )
    expect(page).to have_css("a[target='_blank'][rel='noopener noreferrer']", text: I18n.t("maint_platform.customers.index.act_as"))
  end

  it "places the requester on the left and the viewer's reply on the right" do
    owner = find_or_create_platform_owner
    reply = create(:support_ticket_message, :from_owner, support_ticket: request, user: owner, customer: request.customer, body: "We are looking into this.")

    render_inline(
      described_class.new(
        support_ticket: request,
        messages: [messages.first, reply],
        viewer: owner,
        reply_path: "/81721200/admin/maintenance/platform/support_tickets/#{request.id}/messages",
        resolve_path: "/81721200/admin/maintenance/platform/support_tickets/#{request.id}/resolution",
        owner_view: true
      )
    )

    expect(page).to have_css("article[data-side='theirs'].items-start", text: "Need help with this screen.")
    expect(page).to have_css("article[data-side='mine'].items-end", text: "We are looking into this.")
    expect(page).to have_text(I18n.t("chrome.help_menu.thread.you"))
    expect(page).to have_text(request.user.display_name)
  end
end
