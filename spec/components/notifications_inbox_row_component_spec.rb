# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationsInboxRowComponent, type: :component do
  let(:mark_read_path) { "/42/admin/platform_announcement_reads" }
  let(:support_ticket_read_path) { "/42/admin/support_ticket_reads" }
  let(:announcement) { create(:platform_announcement, :published, title: "Row title", body_en: "Row body") }

  def announcement_item(unread:, link_url: nil)
    Notifications::Inbox::Item.new(
      kind: :announcement,
      id: announcement.id,
      title: announcement.title,
      body: announcement.body_for(:en),
      unread: unread,
      occurred_at: announcement.created_at,
      href: nil,
      subtitle: nil,
      link_url: link_url,
      mark_read_param: :platform_announcement_id,
      mark_read_value: announcement.id
    )
  end

  def render_row(item)
    render_inline(described_class.new(
      item: item, mark_read_path: mark_read_path, support_ticket_read_path: support_ticket_read_path
    ))
  end

  it "renders an unread announcement with an unread dot, kind label, and hidden mark-read form" do
    render_row(announcement_item(unread: true))

    expect(page).to have_css("span.rounded-full.bg-accent[aria-hidden='true']")
    expect(page).to have_css("span.sr-only", text: "Unread")
    expect(page).to have_css("span.text-text-primary", text: "Row title")
    expect(page).to have_css("span.text-text-secondary", text: "Row body")
    expect(page).to have_css("span.text-accent-text", text: "Announcement")
    expect(page).to have_css("time[datetime='#{announcement.created_at.iso8601}']", text: /ago\z/)
    expect(page).to have_css("form[action='#{mark_read_path}'][data-turbo-stream='true']")
    expect(page).to have_field("platform_announcement_id", type: :hidden, with: announcement.id.to_s)
    expect(page).not_to have_css("button[aria-label='Mark as read']")
    expect(page).to have_css("[data-controller='text-expand']")
    expect(page).to have_css("[data-text-expand-target='clamped'][data-limit='#{described_class::TITLE_LIMIT}']", text: "Row title")
    expect(page).to have_css("[data-text-expand-target='clamped'][data-limit='#{described_class::BODY_LIMIT}']", text: "Row body")
    expect(page).to have_css("##{described_class.announcement_dom_id_for(announcement.id)}")
  end

  it "renders a read announcement as muted static text without a mark-read form" do
    render_row(announcement_item(unread: false))

    expect(page).not_to have_css("span.bg-accent")
    expect(page).not_to have_css("span.sr-only", text: "Unread")
    expect(page).to have_css("span.font-medium.text-text-secondary", text: "Row title")
    expect(page).to have_css("span.text-text-tertiary", text: "Row body")
    expect(page).to have_css("[data-text-expand-target='clamped']", text: "Row body")
    expect(page).not_to have_css("form[action='#{mark_read_path}']")
    expect(page).not_to have_button
  end

  it "renders Learn more as a sibling of the mark-read form when link_url is present" do
    linked = create(:platform_announcement, :published, link_url: "https://status.example.com")
    item = Notifications::Inbox::Item.new(
      kind: :announcement,
      id: linked.id,
      title: linked.title,
      body: linked.body_for(:en),
      unread: true,
      occurred_at: linked.created_at,
      href: nil,
      subtitle: nil,
      link_url: linked.link_url,
      mark_read_param: :platform_announcement_id,
      mark_read_value: linked.id
    )
    render_row(item)

    expect(page).to have_link("Learn more", href: "https://status.example.com")
    expect(page).to have_css('a[target="_blank"][rel="noopener noreferrer"][data-turbo="false"]', text: "Learn more")
    expect(page).to have_css("form[action='#{mark_read_path}']")
    expect(page).to have_link("Learn more")
  end

  it "omits Learn more when link_url is blank" do
    render_row(announcement_item(unread: true))
    expect(page).not_to have_link("Learn more")
  end

  it "renders a help ticket as a mark-read POST that navigates to the thread" do
    item = Notifications::Inbox::Item.new(
      kind: :support_ticket,
      id: 9,
      title: "Cannot save",
      body: "The button does nothing.",
      unread: true,
      occurred_at: Time.current,
      href: "/1/admin/support_tickets/9",
      subtitle: "Acme",
      link_url: nil,
      mark_read_param: :support_ticket_id,
      mark_read_value: 9
    )
    render_row(item)

    expect(page).not_to have_link(href: "/1/admin/support_tickets/9")
    expect(page).to have_css("form[action='#{support_ticket_read_path}'][data-turbo='false']")
    expect(page).to have_field("support_ticket_id", type: :hidden, with: "9")
    expect(page).to have_css("form[action='#{support_ticket_read_path}'] button.after\\:absolute")
    expect(page).to have_css("span.text-info", text: "Support ticket")
    expect(page).to have_text("Cannot save")
    expect(page).to have_css("span.truncate", text: "Acme")
    expect(page).not_to have_css("form[action='#{mark_read_path}']")
  end

  it "posts a read help ticket to the same mark-read path" do
    item = Notifications::Inbox::Item.new(
      kind: :support_ticket,
      id: 9,
      title: "Cannot save",
      body: "The button does nothing.",
      unread: false,
      occurred_at: Time.current,
      href: "/1/admin/support_tickets/9",
      subtitle: nil,
      link_url: nil,
      mark_read_param: :support_ticket_id,
      mark_read_value: 9
    )
    render_row(item)

    expect(page).to have_css("form[action='#{support_ticket_read_path}'][data-turbo='false']")
    expect(page).to have_field("support_ticket_id", type: :hidden, with: "9")
  end

  it "keeps the full body in the DOM so a click can expand past the length limit" do
    item = announcement_item(unread: true)
    item.body = "A" * 200
    render_row(item)

    expect(page).to have_css("span[data-text-expand-target='clamped'][data-limit='#{described_class::BODY_LIMIT}']", text: "A" * 200)
  end

  it "omits the preview line when the body is blank" do
    item = announcement_item(unread: true)
    item.body = "  "
    render_row(item)

    expect(page).to have_css("[data-text-expand-target='clamped']", count: 1, text: "Row title")
  end

  it "renders the kind label in Simplified Chinese" do
    I18n.with_locale(:"zh-CN") { render_row(announcement_item(unread: true)) }

    expect(page).to have_css("span.text-accent-text", text: "公告")
    expect(page).to have_css("span.sr-only", text: "未读")
  end
end
