# frozen_string_literal: true

require "rails_helper"

# PATCH /:cid/admin/maintenance/pages/:page_id/flowchart
# Rebinds the flowchart that processes a page's submissions. Owner-only
# (FlowchartVisibility). Shared pages are rebound on the platform prefix only.
RSpec.describe "Admin::Maintenance::FlowchartBindings", type: :request do
  include_context "as platform owner on tenant"

  let(:page_rec) { create(:page, customer: customer) }
  let(:replacement) { create(:flowchart, :simple, :launched_status, customer: customer, name: "Custom save") }

  def binding_path(cid = customer.id, page = page_rec)
    "/#{cid}/admin/maintenance/pages/#{page.id}/flowchart"
  end

  def patch_binding(page: page_rec, cid: customer.id, flowchart: replacement)
    patch binding_path(cid, page), params: { page: { flowchart_id: flowchart.id } }
  end

  let(:guard_path) { binding_path }

  it_behaves_like "a platform-owner-guarded request", :patch

  it "lets the platform owner rebind a tenant page" do
    patch_binding

    expect(response).to redirect_to("/#{customer.id}/admin/maintenance/pages/#{page_rec.id}")
    expect(flash[:notice]).to eq(I18n.t("maint_core.flash.flowchart_bindings.updated", name: replacement.name))
    expect(page_rec.reload.flowchart_id).to eq(replacement.id)
  end

  it "refuses a same-tenant admin" do
    original_id = page_rec.flowchart_id
    sign_in admin
    patch_binding

    expect(response).to have_http_status(:forbidden).or have_http_status(:found)
    expect(page_rec.reload.flowchart_id).to eq(original_id)
  end

  it "refuses a same-tenant member" do
    original_id = page_rec.flowchart_id
    sign_in create(:user, :member, customer: customer)
    patch_binding

    expect(response).to have_http_status(:forbidden).or have_http_status(:found)
    expect(page_rec.reload.flowchart_id).to eq(original_id)
  end

  it "404s for another customer's page" do
    foreign = create(:page, customer: create(:customer))
    patch_binding(page: foreign)

    expect(response).to have_http_status(:not_found)
  end

  it "rejects a shared page on the tenant path" do
    shared = create(:page, :shared, name: "SharedBindingLock")
    shared_flowchart = create(:flowchart, :shared_type, :launched_status, name: "Shared save")

    patch_binding(page: shared, flowchart: shared_flowchart)

    expect(response).to have_http_status(:redirect)
    expect(flash[:alert]).to eq(I18n.t("maint_core.flash.shared_resources.platform_path_only"))
    expect(shared.reload.flowchart_id).not_to eq(shared_flowchart.id)
  end

  it "rebinds a shared page on the platform prefix" do
    owner = find_or_create_platform_owner
    sign_in owner
    cid = owner.customer_id
    shared = create(:page, :shared, name: "SharedBindingOk")
    shared_flowchart = create(:flowchart, :shared_type, :launched_status, name: "Shared save")

    patch "/#{cid}/admin/maintenance/platform/pages/#{shared.id}/flowchart",
          params: { page: { flowchart_id: shared_flowchart.id } }

    expect(response).to redirect_to("/#{cid}/admin/maintenance/platform/pages/#{shared.id}")
    expect(flash[:notice]).to eq(I18n.t("maint_core.flash.flowchart_bindings.updated", name: shared_flowchart.name))
    expect(shared.reload.flowchart_id).to eq(shared_flowchart.id)
  end
end
