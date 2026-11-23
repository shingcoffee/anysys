# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::Inbox do
  let(:customer) { create(:customer, name: "Acme") }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:owner) { find_or_create_platform_owner }

  def items_for(user, customer_id: customer.id)
    described_class.for_viewer(user: user, customer_id: customer_id)
  end

  it "includes a live announcement for a tenant admin" do
    create(:platform_announcement, :published, title: "Maintenance")
    kinds = items_for(admin).map(&:kind)
    expect(kinds).to include(:announcement)
  end

  it "includes the admin's own help ticket and not another tenant's" do
    mine = create(:support_ticket, :with_message, customer: customer, user: admin, subject: "Mine")
    other = create(:customer)
    other_admin = create(:user, :admin, customer: other)
    create(:support_ticket, :with_message, customer: other, user: other_admin, subject: "Theirs")

    titles = items_for(admin).select { |i| i.kind == :support_ticket }.map(&:title)
    expect(titles).to eq([ "Mine" ])
    expect(items_for(admin).find { |i| i.kind == :support_ticket && i.id == mine.id }.href)
      .to eq("/#{customer.id}/admin/support_tickets/#{mine.id}")
  end

  it "shows every tenant's tickets to the platform owner" do
    create(:support_ticket, :with_message, customer: customer, user: admin, subject: "From Acme")

    items = items_for(owner, customer_id: Authentication::User::PLATFORM_CUSTOMER_ID)
    help = items.find { |i| i.kind == :support_ticket && i.title == "From Acme" }
    expect(help).to be_present
    expect(help.subtitle).to eq("Acme")
    expect(help.href).to include("/admin/maintenance/platform/support_tickets/")
    expect(help.unread).to be true
  end

  it "marks a ticket read for the requester after they open it" do
    request = create(:support_ticket, :with_message, customer: customer, user: admin)
    owner_user = owner
    create(:support_ticket_message, :from_owner, support_ticket: request, user: owner_user, customer: customer)
    SupportTicketRead.record!(support_ticket: request, user_id: admin.id)

    item = items_for(admin).find { |i| i.kind == :support_ticket }
    expect(item.unread).to be false
  end

  it "finds an inbox-visible ticket for the viewer and not a peer's" do
    mine = create(:support_ticket, :with_message, customer: customer, user: admin)
    peer = create(:user, :admin, customer: customer)
    theirs = create(:support_ticket, :with_message, customer: customer, user: peer)
    inbox = described_class.new(user: admin, customer_id: customer.id)

    expect(inbox.visible_support_ticket(mine.id)).to eq(mine)
    expect(inbox.visible_support_ticket(theirs.id)).to be_nil
    expect(inbox.thread_path_for(mine)).to eq("/#{customer.id}/admin/support_tickets/#{mine.id}")
  end

  it "lets the platform owner find any tenant ticket and path to the platform thread" do
    ticket = create(:support_ticket, :with_message, customer: customer, user: admin)
    inbox = described_class.new(
      user: owner, customer_id: Authentication::User::PLATFORM_CUSTOMER_ID
    )

    expect(inbox.visible_support_ticket(ticket.id)).to eq(ticket)
    expect(inbox.thread_path_for(ticket)).to include("/admin/maintenance/platform/support_tickets/")
  end

  it "orders unread items by recency" do
    older = create(:platform_announcement, :published, title: "Older unread")
    ticket = create(:support_ticket, :with_message, customer: customer, user: admin, subject: "Newer ticket")
    create(:support_ticket_message, :from_owner, support_ticket: ticket, user: owner, customer: customer)
    older.update_column(:created_at, 2.days.ago)
    ticket.update_column(:last_message_at, 1.hour.ago)

    titles = items_for(admin).map(&:title)
    expect(titles.first(2)).to eq([ "Newer ticket", "Older unread" ])
  end
end
