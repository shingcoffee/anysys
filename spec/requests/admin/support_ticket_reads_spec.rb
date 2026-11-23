# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::SupportTicketReads", type: :request do
  include_context "admin records"
  let(:member) { create(:user, :member, customer: customer) }
  let(:other) { create(:customer) }
  let(:other_admin) { create(:user, :admin, customer: other) }

  def mark_read(ticket, acting_customer: customer)
    post admin_support_ticket_reads_path(acting_customer.id),
         params: { support_ticket_id: ticket.id },
         headers: { "HTTP_REFERER" => admin_dashboard_path(acting_customer.id) }
  end

  def last_read_at(user:, ticket:)
    SupportTicketRead.last_read_at_for(user_id: user.id, support_ticket_id: ticket.id)
  end

  let(:guard_path) { admin_support_ticket_reads_path(customer.id) }

  it_behaves_like "an admin-guarded request", :post

  describe "tenant admin" do
    before { sign_in admin }

    it "records a read and redirects to the tenant thread" do
      ticket = create(:support_ticket, :with_message, customer: customer, user: admin)
      mark_read(ticket)

      expect(last_read_at(user: admin, ticket: ticket)).to be_present
      expect(response).to redirect_to(admin_support_ticket_path(customer.id, ticket))
    end

    it "is idempotent when the same ticket is marked read twice" do
      ticket = create(:support_ticket, :with_message, customer: customer, user: admin)
      mark_read(ticket)
      mark_read(ticket)

      expect(SupportTicketRead.where(support_ticket: ticket, user_id: admin.id).count).to eq(1)
      expect(response).to redirect_to(admin_support_ticket_path(customer.id, ticket))
    end

    it "does not write for a missing id and still redirects" do
      post admin_support_ticket_reads_path(customer.id),
           params: {},
           headers: { "HTTP_REFERER" => admin_dashboard_path(customer.id) }

      expect(SupportTicketRead.count).to eq(0)
      expect(response).to redirect_to(admin_dashboard_path(customer.id))
    end

    it "does not write for a peer admin's ticket" do
      peer = create(:user, :admin, customer: customer)
      ticket = create(:support_ticket, :with_message, customer: customer, user: peer)
      mark_read(ticket)

      expect(SupportTicketRead.count).to eq(0)
      expect(response).to redirect_to(admin_dashboard_path(customer.id))
    end

    it "does not write for another tenant's ticket via the acting tenant URL" do
      ticket = create(:support_ticket, :with_message, customer: other, user: other_admin)
      mark_read(ticket)

      expect(SupportTicketRead.count).to eq(0)
      expect(response).to redirect_to(admin_dashboard_path(customer.id))
    end

    it "does not write for an aged-out resolved ticket" do
      ticket = create(
        :support_ticket, :with_message, :resolved,
        customer: customer, user: admin, last_message_at: 8.days.ago
      )
      mark_read(ticket)

      expect(SupportTicketRead.count).to eq(0)
      expect(response).to redirect_to(admin_dashboard_path(customer.id))
    end
  end

  describe "member" do
    before { sign_in member }

    it "is denied without recording a read" do
      ticket = create(:support_ticket, :with_message, customer: customer, user: admin)
      mark_read(ticket)

      expect(SupportTicketRead.count).to eq(0)
    end
  end

  describe "anonymous" do
    it "does not record a read" do
      ticket = create(:support_ticket, :with_message, customer: customer, user: admin)
      mark_read(ticket)

      expect(SupportTicketRead.count).to eq(0)
    end
  end

  describe "cross-tenant mark-read" do
    it "forbids admin of A from marking read on B's URL and writes nothing" do
      ticket = create(:support_ticket, :with_message, customer: customer, user: admin)

      sign_in admin
      mark_read(ticket, acting_customer: other)

      expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
      expect(response).not_to have_http_status(:ok)
      expect(SupportTicketRead.count).to eq(0)
    end
  end

  describe "platform owner" do
    let(:owner) { find_or_create_platform_owner }
    let(:platform_cid) { ensure_platform_customer.id }

    before { sign_in owner }

    it "records a read for any inbox-visible ticket and redirects to the platform thread" do
      ticket = create(:support_ticket, :with_message, customer: customer, user: admin)
      mark_read(ticket, acting_customer: Customer.find(platform_cid))

      expect(last_read_at(user: owner, ticket: ticket)).to be_present
      expect(response).to redirect_to(
        admin_maintenance_platform_support_ticket_path(
          Authentication::User::PLATFORM_CUSTOMER_ID, ticket
        )
      )
    end

    it "redirects to the platform thread even when acting on a tenant URL" do
      ticket = create(:support_ticket, :with_message, customer: customer, user: admin)
      mark_read(ticket, acting_customer: customer)

      expect(last_read_at(user: owner, ticket: ticket)).to be_present
      expect(response).to redirect_to(
        admin_maintenance_platform_support_ticket_path(
          Authentication::User::PLATFORM_CUSTOMER_ID, ticket
        )
      )
    end
  end
end
