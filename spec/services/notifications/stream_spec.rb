# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::Stream do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:owner) { find_or_create_platform_owner }
  let(:ticket) { create(:support_ticket, :with_message, customer: customer, user: admin) }

  before do
    owner
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
  end

  it "broadcasts a help-unread replace, row upsert, and thread append to the platform owner" do
    described_class.broadcast_help!(request: ticket, message: ticket.latest_message)

    stream = described_class.name(user_id: owner.id)
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      stream,
      target: described_class::SUPPORT_TICKET_UNREAD_ID,
      html: kind_of(String)
    )
    expect(Turbo::StreamsChannel).to have_received(:broadcast_remove_to).with(
      stream,
      target: NotificationsInboxRowComponent.dom_id_for(ticket.id)
    )
    expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to).with(
      stream,
      target: NotificationsInboxComponent::LIST_DOM_ID,
      html: kind_of(String)
    )
    expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to).with(
      stream,
      target: HelpThreadComponent.messages_dom_id(ticket.id),
      html: kind_of(String)
    )
  end

  it "does not broadcast to the author" do
    described_class.broadcast_help!(request: ticket, message: ticket.latest_message)

    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to).with(
      described_class.name(user_id: admin.id), anything
    )
  end

  it "renders the help row in the recipient's locale" do
    owner.update!(locale: "zh-CN")
    described_class.broadcast_help!(request: ticket, message: ticket.latest_message)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to).with(
      described_class.name(user_id: owner.id),
      hash_including(html: a_string_including("前"))
    )
  end

  it "broadcasts owner replies to the requester only" do
    reply = create(:support_ticket_message, :from_owner, support_ticket: ticket, user: owner, customer: customer)
    described_class.broadcast_help!(request: ticket.reload, message: reply)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      described_class.name(user_id: admin.id),
      target: described_class::SUPPORT_TICKET_UNREAD_ID,
      html: kind_of(String)
    )
    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to).with(
      described_class.name(user_id: owner.id), anything
    )
  end

  it "does not clobber announcement rows — only the help-unread target and help row list" do
    described_class.broadcast_help!(request: ticket, message: ticket.latest_message)

    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to).with(
      anything, hash_including(target: NotificationsInboxComponent::PANEL_BODY_DOM_ID)
    )
    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to).with(
      anything, hash_including(target: Notifications::Stream::ANNOUNCEMENT_UNREAD_ID)
    )
  end

  describe ".broadcast_announcement!" do
    let(:other) { create(:customer) }
    let!(:other_admin) { create(:user, :admin, customer: other) }
    let!(:member) { create(:user, :member, customer: customer) }
    let(:notice) { create(:platform_announcement, :published, :all_customers, title: "Live notice") }

    before { admin }

    it "pushes unread, row upsert, and banner replace to matching tenant admins" do
      described_class.broadcast_announcement!(notice)

      stream = described_class.name(user_id: admin.id)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        stream,
        target: described_class::ANNOUNCEMENT_UNREAD_ID,
        html: kind_of(String)
      )
      expect(Turbo::StreamsChannel).to have_received(:broadcast_remove_to).with(
        stream,
        target: NotificationsInboxRowComponent.announcement_dom_id_for(notice.id)
      )
      expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to).with(
        stream,
        target: NotificationsInboxComponent::LIST_DOM_ID,
        html: kind_of(String)
      )
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        stream,
        target: Platform::AnnouncementBannerComponent::STACK_DOM_ID,
        html: kind_of(String)
      )
    end

    it "does not push to a tenant outside a selected audience" do
      selected = create(
        :platform_announcement, :published, :selected,
        target_rules: {
          "type" => "group",
          "joins" => [],
          "conditions" => [ { "field" => "id", "operator" => "equals", "value" => customer.id.to_s } ]
        }
      )
      described_class.broadcast_announcement!(selected)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        described_class.name(user_id: admin.id),
        target: described_class::ANNOUNCEMENT_UNREAD_ID,
        html: kind_of(String)
      )
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to).with(
        described_class.name(user_id: other_admin.id), anything
      )
    end

    it "does not push to members or the platform owner" do
      described_class.broadcast_announcement!(notice)

      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to).with(
        described_class.name(user_id: member.id), anything
      )
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to).with(
        described_class.name(user_id: owner.id), anything
      )
    end

    it "no-ops when the announcement is not live" do
      draft = create(:platform_announcement, :draft, :all_customers)
      described_class.broadcast_announcement!(draft)

      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_prepend_to)
    end
  end

  describe ".broadcast_announcement_removed!" do
    let(:notice) { create(:platform_announcement, :draft, :all_customers) }

    it "removes the inbox row and refreshes the banner for the given users" do
      described_class.broadcast_announcement_removed!(notice, users: [ admin ])

      stream = described_class.name(user_id: admin.id)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        stream,
        target: described_class::ANNOUNCEMENT_UNREAD_ID,
        html: kind_of(String)
      )
      expect(Turbo::StreamsChannel).to have_received(:broadcast_remove_to).with(
        stream,
        target: NotificationsInboxRowComponent.announcement_dom_id_for(notice.id)
      )
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        stream,
        target: Platform::AnnouncementBannerComponent::STACK_DOM_ID,
        html: kind_of(String)
      )
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_prepend_to)
    end
  end

  describe ".refresh_announcement!" do
    it "removes an expired banner while keeping bell history on matching admins' existing streams" do
      admin
      other_admin = create(:user, :admin)
      ends_at = Time.zone.parse("2026-10-11 13:00:00")
      notice = create(:platform_announcement, :published, :selected, ends_at: ends_at, title: "Expired banner",
        target_rules: {
          "type" => "group", "joins" => [],
          "conditions" => [{ "field" => "id", "operator" => "equals", "value" => customer.id.to_s }]
        })

      travel_to(ends_at) { described_class.refresh_announcement!(notice) }

      stream = described_class.name(user_id: admin.id)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        stream, target: Platform::AnnouncementBannerComponent::STACK_DOM_ID,
        html: satisfy { |html| !html.include?("Expired banner") }
      )
      expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to).with(
        stream, target: NotificationsInboxComponent::LIST_DOM_ID, html: a_string_including("Expired banner")
      )
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to).with(
        described_class.name(user_id: other_admin.id), anything
      )
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to).with(
        described_class.name(user_id: owner.id), anything
      )
    end
  end
end
