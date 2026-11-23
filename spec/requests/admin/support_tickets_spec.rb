# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::SupportTickets", type: :request do
  include_context "admin records"
  let(:member) { create(:user, :member, customer: customer) }
  let(:other) { create(:customer) }
  let(:other_admin) { create(:user, :admin, customer: other) }
  let(:guard_path) { admin_support_tickets_path(customer.id) }

  it_behaves_like "an admin-guarded request", :post

  describe "GET show — auth guards" do
    let!(:ticket) { create(:support_ticket, :with_message, customer: customer, user: admin) }
    let(:guard_path) { admin_support_ticket_path(customer.id, ticket) }

    it_behaves_like "an admin-guarded GET"
  end

  describe "POST messages — auth guards" do
    let!(:ticket) { create(:support_ticket, :with_message, customer: customer, user: admin) }
    let(:guard_path) { admin_support_ticket_messages_path(customer.id, ticket) }

    it_behaves_like "an admin-guarded request", :post
  end

  describe "member" do
    before { sign_in member }

    it "is denied without creating a ticket" do
      post admin_support_tickets_path(customer.id), params: { support_ticket: { subject: "Hi", body: "There" } }
      expect(SupportTicket.count).to eq(0)
    end
  end

  describe "tenant admin" do
    before { sign_in admin }

    it "creates a ticket and redirects to the thread" do
      post admin_support_tickets_path(customer.id), params: { support_ticket: { subject: "Stuck", body: "Cannot save a page." } }
      request_row = SupportTicket.last
      expect(request_row).to have_attributes(subject: "Stuck", user_id: admin.id, customer_id: customer.id)
      expect(response).to redirect_to(admin_support_ticket_path(customer.id, request_row))
    end

    it "attaches every uploaded screenshot on create" do
      post admin_support_tickets_path(customer.id), params: {
        support_ticket: {
          subject: "Screenshots",
          body: "See attached.",
          images: [ png_upload("one.png"), png_upload("two.png") ]
        }
      }

      expect(response).to have_http_status(:redirect)
      expect(SupportTicket.last.messages.sole.images.count).to eq(2)
    end

    it "shows their own ticket" do
      ticket = create(:support_ticket, :with_message, customer: customer, user: admin)
      get admin_support_ticket_path(customer.id, ticket)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ticket.subject)
    end

    it "cannot show another tenant's ticket via their own customer URL" do
      ticket = create(:support_ticket, :with_message, customer: other, user: other_admin)
      get admin_support_ticket_path(customer.id, ticket)
      expect(response).to have_http_status(:not_found)
    end

    it "cannot show another admin's ticket in the same tenant" do
      peer = create(:user, :admin, customer: customer)
      ticket = create(:support_ticket, :with_message, customer: customer, user: peer)
      get admin_support_ticket_path(customer.id, ticket)
      expect(response).to have_http_status(:not_found)
    end

    it "appends a requester reply on their own ticket" do
      ticket = create(:support_ticket, :with_message, customer: customer, user: admin)
      post admin_support_ticket_messages_path(customer.id, ticket),
           params: { support_ticket_message: { body: "More detail here." } }

      expect(ticket.messages.order(:id).last).to have_attributes(author_role: "requester", body: "More detail here.")
      expect(response).to redirect_to(admin_support_ticket_path(customer.id, ticket))
    end
  end

  describe "platform owner" do
    let(:owner) { find_or_create_platform_owner }

    before { sign_in owner }

    it "cannot create a notify ticket" do
      post admin_support_tickets_path(customer.id), params: { support_ticket: { subject: "Hi", body: "There" } }
      expect(SupportTicket.count).to eq(0)
      expect(response).to redirect_to(admin_dashboard_path(customer.id))
    end
  end
end
