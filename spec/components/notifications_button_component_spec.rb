# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationsButtonComponent, type: :component do
  include Rails.application.routes.url_helpers

  let(:customer) { create(:customer, name: "Acme") }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:member) { create(:user, :member, customer: customer) }
  let(:reads_url) { admin_platform_announcement_reads_path(customer.id) }

  after { Current.reset }

  def build_component(user: admin, **opts)
    described_class.new(user: user, customer_id: customer.id, **opts)
  end

  it "renders a bell button with no badge by default" do
    render_inline(described_class.new)
    expect(page).to have_css("button[aria-label='Notifications']")
    expect(page).not_to have_css("[data-badge-count]")
  end

  it "keeps the Stimulus root around the trigger, badge, and panel" do
    render_inline(described_class.new)

    expect(page).to have_css("[data-controller='notifications-menu']")
    expect(page).not_to have_css("#notifications-bell-inner")
    expect(page).to have_css("#notifications-trigger")
    expect(page).to have_css("#notifications-badge")
    expect(page).to have_css("[data-action='click->notifications-menu#toggle']")
    expect(page).to have_css("[data-notifications-menu-target='trigger']")
    expect(page).to have_css("[data-notifications-menu-target='panel']", visible: :all)
    expect(page).to have_css("[data-notifications-menu-target='headerBadge']", visible: :all)
    expect(page).to have_css("[role='dialog'][aria-label='Notifications']", visible: :all)
  end

  it "hides the panel by default" do
    render_inline(described_class.new)
    panel = page.find("[data-notifications-menu-target='panel']", visible: :all)

    expect(panel[:class].split).to include("hidden")
    expect(page).to have_css("button[aria-expanded='false']")
  end

  it "shows a badge, title, and English body for an admin with a live announcement" do
    create(:platform_announcement, :published, title: "Scheduled maintenance", body_en: "We will be down for maintenance.")
    render_inline(build_component)

    expect(page).to have_css("[data-badge-count='1']", text: "1")
    expect(page).to have_css("#notifications-panel-body", text: "Scheduled maintenance", visible: :all)
    expect(page).to have_css("#notifications-panel-body", text: "We will be down for maintenance.", visible: :all)
    expect(page).to have_css("button[aria-label='Notifications, 1 unread']")
  end

  it "renders the Chinese body when the locale is zh-CN" do
    create(:platform_announcement, :published, body_zh: "系统将进行维护。")
    I18n.with_locale(:"zh-CN") do
      render_inline(build_component)
    end

    expect(page).to have_css("#notifications-panel-body", text: "系统将进行维护。", visible: :all)
  end

  it "uses unread_titled as the trigger aria-label when unread count is positive" do
    create(:platform_announcement, :published)
    render_inline(build_component)

    expect(page).to have_css("button[aria-label='Notifications, 1 unread']")
  end

  it "lists a read announcement as muted history without a badge" do
    announcement = create(:platform_announcement, :published, title: "Already seen")
    PlatformAnnouncementRead.record!(
      announcement: announcement, user_id: admin.id, customer_id: customer.id
    )
    render_inline(build_component)

    expect(page).not_to have_css("[data-badge-count]")
    expect(page).to have_css("#notifications-panel-body", text: "Already seen", visible: :all)
    expect(page).to have_css("span.font-medium.text-text-secondary", text: "Already seen", visible: :all)
    expect(page).not_to have_css("span.bg-accent")
    expect(page).to have_css("button[aria-label='Notifications']")
  end

  it "renders Learn more when link_url is present" do
    create(:platform_announcement, :published, link_url: "https://status.example.com")
    render_inline(build_component)

    expect(page).to have_link("Learn more", href: "https://status.example.com", visible: :all)
    expect(page).to have_css('a[target="_blank"][rel="noopener noreferrer"][data-turbo="false"]', text: "Learn more", visible: :all)
  end

  it "omits Learn more when link_url is blank" do
    create(:platform_announcement, :published, link_url: nil)
    render_inline(build_component)

    expect(page).not_to have_link("Learn more", visible: :all)
  end

  it "shows the empty state when the inbox has no items" do
    create(:platform_announcement, :draft)
    render_inline(build_component)

    expect(page).to have_css("#notifications-panel-body", text: "You're all caught up", visible: :all)
    expect(page).to have_css("#notifications-panel-body", text: "No new notifications right now.", visible: :all)
    expect(page).not_to have_css("[data-badge-count]")
  end

  it "orders unread rows before newer read rows" do
    older_unread = create(:platform_announcement, :published, title: "Older unread")
    newer_read = create(:platform_announcement, :published, title: "Newer read")
    older_unread.update_column(:created_at, 2.days.ago)
    newer_read.update_column(:created_at, 1.day.ago)
    PlatformAnnouncementRead.record!(
      announcement: newer_read, user_id: admin.id, customer_id: customer.id
    )
    render_inline(build_component)

    titles = page.all("#notifications-panel-body span.block.text-sm", visible: :all).map(&:text)
    expect(titles).to eq([ "Older unread", "Newer read" ])
  end

  it "does not leak announcement titles to a member viewer" do
    create(:platform_announcement, :published, title: "Secret notice")
    render_inline(build_component(user: member))

    expect(page).not_to have_css("[data-badge-count]")
    expect(page).not_to have_css("#notifications-panel-body", text: "Secret notice", visible: :all)
    expect(page).to have_css("#notifications-panel-body", text: "You're all caught up", visible: :all)
  end

  it "does not leak announcement titles when there is no signed-in viewer" do
    create(:platform_announcement, :published, title: "Secret notice")
    render_inline(build_component(user: nil))

    expect(page).not_to have_css("[data-badge-count]")
    expect(page).not_to have_css("#notifications-panel-body", text: "Secret notice", visible: :all)
    expect(page).to have_css("#notifications-panel-body", text: "You're all caught up", visible: :all)
  end

  it "posts mark-read to the reads path" do
    announcement = create(:platform_announcement, :published)
    render_inline(build_component)

    expect(page).to have_css("form[action='#{reads_url}'][data-turbo-stream='true']", visible: :all)
    expect(page).to have_field("platform_announcement_id", type: :hidden, with: announcement.id.to_s, visible: :all)
    expect(page).to have_css("[data-controller='text-expand']", visible: :all)
  end

  it "posts help tickets to the help mark-read path" do
    ticket = create(:support_ticket, :with_message, customer: customer, user: admin, subject: "Need a hand")
    render_inline(build_component)

    help_url = admin_support_ticket_reads_path(customer.id)
    expect(page).to have_css("form[action='#{help_url}'][data-turbo='false']", visible: :all)
    expect(page).to have_field("support_ticket_id", type: :hidden, with: ticket.id.to_s, visible: :all)
    expect(page).to have_css("#notifications-panel-body", text: "Need a hand", visible: :all)
  end

  it "uses the overflow i18n key when unread count is 100 or more" do
    component = build_component
    render_inline(component)
    allow(component).to receive(:unread_count).and_return(100)

    expect(component.badge_label).to eq("99+")
  end

end
