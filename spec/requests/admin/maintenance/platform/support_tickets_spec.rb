# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::SupportTickets", type: :request do
  let(:platform_owner) { find_or_create_platform_owner }
  let(:platform_cid) { ensure_platform_customer.id }
  let(:tenant) { create(:customer, name: "Acme") }
  let(:tenant_admin) { create(:user, :admin, customer: tenant) }
  let(:guard_path) { admin_maintenance_platform_support_tickets_path(platform_cid) }

  it_behaves_like "a platform-owner-guarded GET"

  describe "GET show — auth guards" do
    let(:ticket) { create(:support_ticket, :with_message, customer: tenant, user: tenant_admin) }
    let(:guard_path) { admin_maintenance_platform_support_ticket_path(platform_cid, ticket) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "POST messages — auth guards" do
    let(:ticket) { create(:support_ticket, :with_message, customer: tenant, user: tenant_admin) }
    let(:guard_path) { admin_maintenance_platform_support_ticket_messages_path(platform_cid, ticket) }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "POST resolution — auth guards" do
    let(:ticket) { create(:support_ticket, :with_message, customer: tenant, user: tenant_admin) }
    let(:guard_path) { admin_maintenance_platform_support_ticket_resolution_path(platform_cid, ticket) }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "platform owner" do
    before { sign_in platform_owner }

    it "lists tickets from every tenant" do
      ticket = create(:support_ticket, :with_message, customer: tenant, user: tenant_admin, subject: "Need help")
      get admin_maintenance_platform_support_tickets_path(platform_cid)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Need help")
      expect(response.body).to include("Acme")
      expect(response.body).to include("Unread")
      expect(response.body).to include("Need help with this screen.")

      get admin_maintenance_platform_support_ticket_path(platform_cid, ticket)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Need help with this screen.")
      expect(response.body).to include("Act As")
      expect(response.body).to include(%(href="/#{tenant.id}/admin/dashboard"))
      expect(response.body).to include(%(target="_blank"))
      expect(response.body).to include("hidden md:flex md:flex-col w-60 lg:w-64 xl:w-72")
      expect(response.body).to include(I18n.t("maint_platform.support_tickets.breadcrumb.maintenance"))
    end

    it "records a reply as the owner role" do
      ticket = create(:support_ticket, :with_message, customer: tenant, user: tenant_admin)
      post admin_maintenance_platform_support_ticket_messages_path(platform_cid, ticket),
           params: { support_ticket_message: { body: "We will take a look." } }

      expect(ticket.messages.order(:id).last).to have_attributes(author_role: "owner", body: "We will take a look.")
      expect(response).to redirect_to(admin_maintenance_platform_support_ticket_path(platform_cid, ticket))
    end

    it "marks a ticket resolved" do
      ticket = create(:support_ticket, :with_message, customer: tenant, user: tenant_admin)
      post admin_maintenance_platform_support_ticket_resolution_path(platform_cid, ticket)
      expect(ticket.reload).to be_resolved
    end
  end
end
