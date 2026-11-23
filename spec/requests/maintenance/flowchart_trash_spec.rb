# frozen_string_literal: true

require "rails_helper"

# Soft-delete / trash lifecycle for flowcharts (parity with entities & pages):
# delete -> trash, restore, empty trash.
RSpec.describe "Maintenance::Flowcharts trash", type: :request do
  include_context "as platform owner on tenant"
  let(:guard_path) { "/#{customer.id}/admin/maintenance/flowcharts" }

  it_behaves_like "a platform-owner-guarded GET"

  let(:entity)     { create(:entity, customer: customer) }
  let!(:flowchart) { create(:flowchart, :draft, customer: customer, name: "Trashable Flow") }

  describe "GET trash — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/flowcharts/trash" }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "DELETE destroy — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}" }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  describe "PATCH restoration — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/restoration" }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "DELETE empty_trash — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/flowcharts/empty_trash" }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  it "exposes a Trash link on the flowchart list" do
    get "/#{customer.id}/admin/maintenance/flowcharts"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("/#{customer.id}/admin/maintenance/flowcharts/trash")
  end

  it "soft-deletes a flowchart (moves it to trash) rather than destroying it" do
    delete "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}"
    expect(flowchart.reload).to be_deleted
    expect(Flowchart.unscoped.exists?(flowchart.id)).to be(true) # still in the DB, just trashed
  end

  it "lists trashed flowcharts on the trash page" do
    flowchart.soft_delete
    get "/#{customer.id}/admin/maintenance/flowcharts/trash"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Trashable Flow")
  end

  it "does not dump every trashed flowchart on one fake page" do
    first = create(:flowchart, customer: customer, name: "DumpA")
    second = create(:flowchart, customer: customer, name: "DumpB")
    first.soft_delete
    second.soft_delete

    get "/#{customer.id}/admin/maintenance/flowcharts/trash", params: { per_page: 1 }

    expect(response).to have_http_status(:ok)
    shown = [response.body.include?("DumpA"), response.body.include?("DumpB")]
    expect(shown.count(true)).to eq(1)
    expect(response.body).to include(
      I18n.t("maint_core.flowcharts.trash.empty_confirm", count: 2)
    )
  end

  it "does not show trashed flowcharts on the main list" do
    flowchart.soft_delete
    get "/#{customer.id}/admin/maintenance/flowcharts"
    expect(response.body).not_to include("Trashable Flow")
  end

  it "restores a flowchart from trash" do
    flowchart.soft_delete
    patch "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/restoration"
    expect(flowchart.reload).not_to be_deleted
  end

  it "permanently deletes everything when emptying the trash" do
    flowchart.soft_delete
    expect {
      delete "/#{customer.id}/admin/maintenance/flowcharts/empty_trash"
    }.to change { Flowchart.unscoped.where(id: flowchart.id).count }.from(1).to(0)
  end

  it "isolates trash by tenant (cannot restore another customer's flowchart)" do
    flowchart.soft_delete
    other = create(:customer)
    sign_in create(:user, customer: other, role: :admin)
    patch "/#{other.id}/admin/maintenance/flowcharts/#{flowchart.id}/restoration"
    expect(response.status).not_to eq(200)
    expect(flowchart.reload).to be_deleted
  end
end
