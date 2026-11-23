# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationsInboxComponent, type: :component do
  let(:mark_read_path) { "/42/admin/platform_announcement_reads" }
  let(:support_ticket_read_path) { "/42/admin/support_ticket_reads" }

  def render_inbox(items)
    render_inline(described_class.new(
      items: items, mark_read_path: mark_read_path, support_ticket_read_path: support_ticket_read_path
    ))
  end

  def item_for(announcement, unread:)
    Notifications::Inbox::Item.new(
      kind: :announcement,
      id: announcement.id,
      title: announcement.title,
      body: announcement.body_for(:en),
      unread: unread,
      occurred_at: announcement.created_at,
      href: nil,
      subtitle: nil,
      link_url: announcement.link_url,
      mark_read_param: :platform_announcement_id,
      mark_read_value: announcement.id
    )
  end

  it "renders the compact empty state when there are no items" do
    render_inbox([])

    expect(page).to have_css("#notifications-panel-body")
    expect(page).to have_text("You're all caught up")
    expect(page).to have_text("No new notifications right now.")
    expect(page).not_to have_css("form[action='#{mark_read_path}']")
  end

  it "renders unread and read rows in the given order" do
    unread = create(:platform_announcement, :published, title: "Unread row")
    read = create(:platform_announcement, :published, title: "Read row")
    render_inbox([
      item_for(unread, unread: true),
      item_for(read, unread: false)
    ])

    titles = page.all("span.block.text-sm").map(&:text)
    expect(titles).to eq([ "Unread row", "Read row" ])
    expect(page).to have_css("form[action='#{mark_read_path}']", count: 1)
    expect(page).to have_css("span.bg-accent")
    expect(page).to have_css("span.font-medium.text-text-secondary", text: "Read row")
  end

  it "posts help tickets to the help mark-read path" do
    item = Notifications::Inbox::Item.new(
      kind: :support_ticket,
      id: 9,
      title: "Need a hand",
      body: "The page will not save.",
      unread: true,
      occurred_at: Time.current,
      href: "/42/admin/support_tickets/9",
      subtitle: nil,
      link_url: nil,
      mark_read_param: :support_ticket_id,
      mark_read_value: 9
    )
    render_inbox([ item ])

    expect(page).to have_css("form[action='#{support_ticket_read_path}'][data-turbo='false']")
    expect(page).to have_field("support_ticket_id", type: :hidden, with: "9")
    expect(page).not_to have_css("form[action='#{mark_read_path}']")
  end
end
