# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin entity entries routing", type: :routing do
  let(:cid) { "12345678" }
  let(:entries_path) { "/#{cid}/admin/entities/42/entries" }
  let(:target) { { controller: "admin/entity_entries", customer_id: cid, entity_id: "42" } }

  it "routes the browse creation form, whose page submits to its own public endpoint" do
    expect(get: "#{entries_path}/new").to route_to(target.merge(action: "new"))
    expect(post: entries_path).not_to be_routable
  end

  it "provides the creation form path helper" do
    expect(Rails.application.routes.url_helpers.new_admin_entity_entry_path(cid, 42)).to eq("#{entries_path}/new")
  end

  it "preserves browse show, destroy, and collection batch destroy" do
    expect(get: "#{entries_path}/7").to route_to(target.merge(action: "show", id: "7"))
    expect(delete: "#{entries_path}/7").to route_to(target.merge(action: "destroy", id: "7"))
    expect(delete: "#{entries_path}/batch").to route_to(target.merge(action: "batch_destroy"))
  end

  it "routes the browse edit form, whose page submits to its own public endpoint" do
    expect(get: "#{entries_path}/7/edit").to route_to(target.merge(action: "edit", id: "7"))
    expect(patch: "#{entries_path}/7").not_to be_routable
    expect(put: "#{entries_path}/7").not_to be_routable
    expect(Rails.application.routes.url_helpers.edit_admin_entity_entry_path(cid, 42, 7)).to eq("#{entries_path}/7/edit")
  end

  it "does not expose a browse index" do
    expect(get: entries_path).not_to be_routable
  end

  it "does not mount an entries list under entity maintenance" do
    maintenance_path = "/#{cid}/admin/maintenance/entities/42/entries"

    expect(get: maintenance_path).not_to be_routable
    expect(delete: "#{maintenance_path}/7").not_to be_routable
    expect(get: "#{maintenance_path}/new").not_to be_routable
    expect(post: maintenance_path).not_to be_routable
    expect(get: "#{maintenance_path}/7/edit").not_to be_routable
    expect(patch: "#{maintenance_path}/7").not_to be_routable
  end

  it "does not mount entries under platform entity maintenance" do
    platform_path = "/81721200/admin/maintenance/platform/entities/42/entries"

    expect(get: "#{platform_path}/new").not_to be_routable
    expect(post: platform_path).not_to be_routable
    expect(get: "#{platform_path}/7/edit").not_to be_routable
    expect(patch: "#{platform_path}/7").not_to be_routable
  end

  it "routes an entry's association rows by bridge entity id" do
    rows_path = "#{entries_path}/7/associations/9/entries"
    rows = { controller: "admin/entity_association_entries", customer_id: cid, entity_id: "42", entry_id: "7", association_id: "9" }

    expect(get: "#{rows_path}/new").to route_to(rows.merge(action: "new"))
    expect(post: rows_path).to route_to(rows.merge(action: "create"))
    expect(get: "#{rows_path}/3/edit").to route_to(rows.merge(action: "edit", id: "3"))
    expect(patch: "#{rows_path}/3").to route_to(rows.merge(action: "update", id: "3"))
    expect(delete: "#{rows_path}/3").to route_to(rows.merge(action: "destroy", id: "3"))
    expect(get: "#{rows_path}/3").not_to be_routable
    expect(get: rows_path).not_to be_routable
  end
end
