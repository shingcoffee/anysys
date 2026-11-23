# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Assignment do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:agents) do
    [
      { "id" => "ann", "weight" => 1, "open_items" => 5, "available" => true },
      { "id" => "bo", "weight" => 3, "open_items" => 1, "available" => true },
      { "id" => "cy", "weight" => 1, "open_items" => 9, "available" => false }
    ]
  end

  def pick(ctx, candidates = agents, **opts)
    described_class.pick(
      ctx,
      candidates,
      strategy: opts.fetch(:strategy, "first"),
      pool_key: opts.fetch(:pool_key, "default"),
      weight_field: opts.fetch(:weight_field, "weight"),
      load_field: opts.fetch(:load_field, "open_items"),
      availability_field: opts[:availability_field],
      exclude: opts[:exclude],
      id_field: opts.fetch(:id_field, "id"),
      returns: opts.fetch(:returns, "candidate")
    )
  end

  it "reads availability, load and id fields from records" do
    entity = create(:entity, customer: customer, property_schema: [
      { "name" => "Open items", "name_slug" => "open_items", "data_type" => "integer" },
      { "name" => "Available", "name_slug" => "available", "data_type" => "boolean" }
    ].to_json)
    records = [[5, true], [1, true], [0, "false"]].map do |load, available|
      entry = create(:entity_entry, :with_data, entity: entity, customer: customer,
                                                entry_data: { "open_items" => load, "available" => available })
      EntityEntry.build_for(entity).find(entry.id)
    end

    chosen = pick({ customer_id: customer.id }, records, strategy: "least_loaded", availability_field: "available")
    expect(chosen).to eq(records[1])
    expect(pick({ customer_id: customer.id }, records, exclude: records[0].id, returns: "id")).to eq(records[1].id)
  end

  it "picks the first eligible candidate" do
    expect(pick({ customer_id: customer.id })["id"]).to eq("ann")
  end

  it "returns only the id when asked" do
    expect(pick({ customer_id: customer.id }, returns: "id")).to eq("ann")
  end

  it "skips unavailable candidates and excluded ids" do
    chosen = pick({ customer_id: customer.id }, availability_field: "available", exclude: "ann")
    expect(chosen["id"]).to eq("bo")
  end

  it "accepts a single exclude id or a list without splitting strings" do
    expect(pick({ customer_id: customer.id }, exclude: "ann")["id"]).to eq("bo")
    expect(pick({ customer_id: customer.id }, exclude: %w[ann bo])["id"]).to eq("cy")
  end

  it "picks the least-loaded eligible candidate" do
    expect(pick({ customer_id: customer.id }, strategy: "least_loaded")["id"]).to eq("bo")
  end

  it "picks by weight using a stubbed random draw" do
    allow(SecureRandom).to receive(:random_number).and_return(0.0)
    expect(pick({ customer_id: customer.id }, strategy: "weighted")["id"]).to eq("ann")
    allow(SecureRandom).to receive(:random_number).and_return(0.99)
    expect(pick({ customer_id: customer.id }, strategy: "weighted")["id"]).to eq("cy")
  end

  it "picks a random eligible index" do
    allow(SecureRandom).to receive(:random_number).with(3).and_return(1)
    expect(pick({ customer_id: customer.id }, strategy: "random")["id"]).to eq("bo")
  end

  it "rotates round-robin through a tenant-scoped counter" do
    ctx = { customer_id: customer.id }
    expect(pick(ctx, strategy: "round_robin")["id"]).to eq("ann")
    expect(pick(ctx, strategy: "round_robin")["id"]).to eq("bo")
    expect(pick(ctx, strategy: "round_robin")["id"]).to eq("cy")
    expect(pick(ctx, strategy: "round_robin")["id"]).to eq("ann")
  end

  it "keeps round-robin counters independent across tenants" do
    pick({ customer_id: customer.id }, strategy: "round_robin", pool_key: "desk")
    other_first = pick({ customer_id: other.id }, strategy: "round_robin", pool_key: "desk")
    expect(other_first["id"]).to eq("ann")
  end

  it "returns nil when the pool is empty" do
    expect(pick({ customer_id: customer.id }, [])).to be_nil
  end

  it "picks scalar candidates by value" do
    expect(pick({ customer_id: customer.id }, %w[ann bo], exclude: "ann")).to eq("bo")
  end

  it "raises for an unknown strategy" do
    expect { pick({ customer_id: customer.id }, strategy: "bogus") }
      .to raise_error(described_class::Error, /unknown strategy/)
  end

  it "raises when round-robin has no customer_id" do
    expect { pick({}, strategy: "round_robin") }
      .to raise_error(described_class::Error, /customer_id/)
  end

  it "lists active users of a reserved role for this tenant only" do
    admin = create(:user, :admin, customer: customer)
    member = create(:user, :member, customer: customer)
    foreign = create(:user, :admin, customer: other)
    inactive = create(:user, :admin, customer: customer, status: :inactive)

    pool = described_class.users_of_role({ customer_id: customer.id }, "admin")
    expect(pool).to include(admin)
    expect(pool).not_to include(member, foreign, inactive)
    expect(pool.map(&:customer_id).uniq).to eq([customer.id])
    expect(described_class.users_of_role({ customer_id: customer.id }, "owner")).to eq([])
    expect(described_class.users_of_role({}, "admin")).to eq([])
  end
end
