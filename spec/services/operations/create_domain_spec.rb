# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::CreateDomain do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }
  let_it_be(:admin) { create(:user, :admin, customer: customer) }
  let_it_be(:foreign_admin) { create(:user, :admin, customer: other) }
  let_it_be(:member) { create(:user, :member, customer: customer) }
  let(:context) { Operations::Context.new(customer: customer, actor: admin, channel: "assistant") }

  def run(input, ctx: context)
    Operations::Activities::Execute.call(operation: "create_domain", input: input, context: ctx)
  end

  it "creates a domain and returns its name, description, color, and an effect" do
    outcome = run({ "name" => "Academics", "description" => "Courses and students.", "color" => "blue" })

    expect(outcome.status).to eq("succeeded"), Array(outcome.violations).map(&:as_json).inspect
    expect(outcome.data["domain"]).to eq(
      "name" => "Academics",
      "description" => "Courses and students.",
      "color" => "blue"
    )
    expect(outcome.effects).to eq([{ "kind" => "domain", "action" => "created", "name" => "Academics" }])

    domain = EntityDomain.find_by_name(customer.id, "Academics")
    expect(domain).to have_attributes(customer_id: customer.id, description: "Courses and students.", color: "blue")
  end

  it "defaults a blank colour to slate" do
    outcome = run({ "name" => "Ticketing" })

    expect(outcome.status).to eq("succeeded")
    expect(outcome.data["domain"]["color"]).to eq("slate")
    expect(EntityDomain.find_by_name(customer.id, "Ticketing").color).to eq("slate")
  end

  it "refuses a name already used by this customer, case-insensitively" do
    create(:entity_domain, customer: customer, name: "Academics")

    outcome = run({ "name" => "academics" })

    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.map { |violation| [violation.code, violation.pointer] })
      .to eq([["entity_domain.already_exists", "/name"]])
    expect(outcome.violations.first.details["name"]).to eq("academics")
    expect(EntityDomain.for_customer(customer.id).count).to eq(1)
  end

  it "rejects an invalid colour at the schema" do
    outcome = run({ "name" => "Academics", "color" => "orange" })

    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.map(&:code)).to include("schema.enum")
    expect(EntityDomain.find_by_name(customer.id, "Academics")).to be_nil
  end

  it "forbids a member and does not write" do
    ctx = Operations::Context.new(customer: customer, actor: member, channel: "assistant")
    outcome = run({ "name" => "Academics" }, ctx: ctx)

    expect(outcome.status).to eq("forbidden")
    expect(EntityDomain.find_by_name(customer.id, "Academics")).to be_nil
  end

  it "forbids an admin of another customer and does not write" do
    ctx = Operations::Context.new(customer: customer, actor: foreign_admin, channel: "assistant")
    outcome = run({ "name" => "Academics" }, ctx: ctx)

    expect(outcome.status).to eq("forbidden")
    expect(EntityDomain.find_by_name(customer.id, "Academics")).to be_nil
  end

  it "lets two customers use the same domain name" do
    create(:entity_domain, customer: other, name: "Academics")

    outcome = run({ "name" => "Academics" })

    expect(outcome.status).to eq("succeeded")
    expect(EntityDomain.find_by_name(customer.id, "Academics")).to be_present
    expect(EntityDomain.find_by_name(other.id, "Academics")).to be_present
  end

  it "replays a stored outcome for the same idempotency key and digest" do
    ctx = Operations::Context.new(
      customer: customer, actor: admin, channel: "assistant", idempotency_key: "gen-domain-1"
    )
    first = run({ "name" => "Academics" }, ctx: ctx)
    second = run({ "name" => "Academics" }, ctx: ctx)

    expect(first.status).to eq("succeeded")
    expect(second.replayed).to be(true)
    expect(second.status).to eq("succeeded")
    expect(EntityDomain.for_customer(customer.id).where("LOWER(name) = ?", "academics").count).to eq(1)
    expect(OperationInvocation.where(customer_id: customer.id, idempotency_key: "gen-domain-1").count).to eq(1)
  end

  it "returns a dry_run plan without writing" do
    ctx = Operations::Context.new(customer: customer, actor: admin, channel: "assistant", dry_run: true)
    outcome = run({ "name" => "Academics" }, ctx: ctx)

    expect(outcome.status).to eq("dry_run")
    expect(outcome.plan).to eq([{ "kind" => "domain", "action" => "created", "name" => "Academics" }])
    expect(EntityDomain.find_by_name(customer.id, "Academics")).to be_nil
    expect(OperationInvocation.where(operation: "create_domain")).to be_empty
  end
end
