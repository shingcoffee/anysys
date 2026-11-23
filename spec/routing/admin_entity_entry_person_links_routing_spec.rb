# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin entity entry person_link routing", type: :routing do
  let(:cid) { "12345678" }
  let(:path) { "/#{cid}/admin/entities/42/entries/7/person_link" }
  let(:target) do
    {
      controller: "admin/entity_entry_person_links",
      customer_id: cid,
      entity_id: "42",
      entry_id: "7"
    }
  end

  it "routes create and candidates under the admin entries nest" do
    expect(post: path).to route_to(target.merge(action: "create"))
    expect(get: "#{path}/candidates").to route_to(target.merge(action: "candidates"))
  end

  it "does not expose show, new, edit, update, or destroy" do
    expect(delete: path).not_to be_routable
    expect(get: path).not_to be_routable
    expect(get: "#{path}/new").not_to be_routable
    expect(get: "#{path}/edit").not_to be_routable
    expect(patch: path).not_to be_routable
    expect(put: path).not_to be_routable
  end

  it "exposes the nested admin helper names" do
    helpers = Rails.application.routes.url_helpers

    expect(helpers.admin_entity_entry_person_link_path(cid, 42, 7)).to eq(path)
    expect(helpers.candidates_admin_entity_entry_person_link_path(cid, 42, 7)).to eq("#{path}/candidates")
  end
end
