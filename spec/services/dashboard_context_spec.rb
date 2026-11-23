# frozen_string_literal: true

require "rails_helper"

RSpec.describe DashboardContext do
  def build_context(**overrides)
    defaults = { current_user: nil, current_customer: nil, current_menu_item: :pages, request_path: "/" }
    described_class.new(**defaults.merge(overrides))
  end

  it "exposes keyword-init fields" do
    ctx = build_context(
      current_user: :user, current_customer: :cust,
      current_menu_item: :entities, request_path: "/x"
    )
    expect(ctx.current_user).to eq(:user)
    expect(ctx.current_customer).to eq(:cust)
    expect(ctx.current_menu_item).to eq(:entities)
    expect(ctx.request_path).to eq("/x")
  end

  it "exposes customer_id from the current_customer" do
    customer = Struct.new(:id).new(42)
    ctx = build_context(current_customer: customer)
    expect(ctx.customer_id).to eq(42)
  end

  it "returns nil customer_id when no customer is set" do
    ctx = build_context(current_customer: nil)
    expect(ctx.customer_id).to be_nil
  end
end
