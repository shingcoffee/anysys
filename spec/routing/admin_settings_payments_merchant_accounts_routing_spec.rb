# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/modules/payments/merchant_accounts routing", type: :routing do
  let(:cid)  { "12345678" }
  let(:ctrl) { "admin/settings/modules/payments/merchant_accounts" }

  it "routes GET index" do
    expect(get: "/#{cid}/#{ctrl}").to route_to(
      controller: ctrl,
      action:     "index",
      customer_id: cid
    )
  end

  it "routes GET new" do
    expect(get: "/#{cid}/#{ctrl}/new").to route_to(
      controller: ctrl,
      action:     "new",
      customer_id: cid
    )
  end

  it "routes POST create" do
    expect(post: "/#{cid}/#{ctrl}").to route_to(
      controller: ctrl,
      action:     "create",
      customer_id: cid
    )
  end

  it "routes GET edit" do
    expect(get: "/#{cid}/#{ctrl}/5/edit").to route_to(
      controller: ctrl,
      action:     "edit",
      customer_id: cid,
      id:          "5"
    )
  end

  it "routes PATCH update" do
    expect(patch: "/#{cid}/#{ctrl}/5").to route_to(
      controller: ctrl,
      action:     "update",
      customer_id: cid,
      id:          "5"
    )
  end

  it "routes POST test_connection as a member route" do
    expect(post: "/#{cid}/#{ctrl}/5/test_connection").to route_to(
      controller: ctrl,
      action:     "test_connection",
      customer_id: cid,
      id:          "5"
    )
  end

  it "does not route DELETE (destroy is excluded)" do
    expect(delete: "/#{cid}/#{ctrl}/5").not_to be_routable
  end
end
