# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::StartSubsystemBuild do
  include ActiveJob::TestHelper

  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:owner) { find_or_create_platform_owner }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: owner) }
  let(:context) { Operations::Context.new(customer: customer, actor: owner, channel: "assistant", conversation: conversation) }
  let(:input) { venue_brief }

  before { say("Build venue bookings. Email the team at bookings@club.test.") }

  def say(body, in_conversation: conversation)
    create(:ai_assistant_message, conversation: in_conversation, customer: customer, role: "user", body: body)
  end

  def run(payload = input, ctx: context)
    Operations::Activities::Execute.call(operation: "start_subsystem_build", input: payload, context: ctx)
  end

  it "records the build from the brief at its first stage and enqueues the job" do
    outcome = nil
    expect { outcome = run }.to have_enqueued_job(AiAssistant::SubsystemBuildJob)

    expect(outcome.status).to eq("succeeded"), outcome.violations.map(&:as_json).inspect
    build = AiAssistant::SubsystemBuild.for_customer(customer.id).sole
    expect(build).to have_attributes(conversation: conversation, user: owner, status: "running", stage: "domain")
    expect(build.blueprint.keys).to eq(%w[domain brief])
    expect(build.blueprint["brief"]).to include(input.except("people")).and include("not_covered" => [])
    expect(build.blueprint["brief"]["people"]).to eq([input["people"].first.merge("sign_in" => "none")])
    expect(build.brief.domain_name).to eq("Venue Bookings")
    expect(outcome.data).to eq("build" => build.id, "status" => "running", "domain" => "Venue Bookings", "warnings" => [])
    expect(outcome.effects).to eq([{ "kind" => "subsystem_build", "action" => "started", "name" => "Venue Bookings" }])
  end

  it "describes a brief and never says flowchart" do
    definition = described_class.tool_definition(context)

    expect(definition.to_json).not_to match(/flowchart/i)
    expect(definition[:parameters]["required"]).to eq(%w[domain summary people scenarios])
  end

  it "rejects a scenario started by someone not in people" do
    scenario = input["scenarios"].first.merge("actor" => "Booking staff")

    outcome = run(input.merge("scenarios" => [scenario]))

    expect(outcome.violations.map { |violation| [violation.code, violation.pointer] }).to eq([["subsystem.actor_unknown", "/scenarios/0/actor"]])
    expect(outcome.violations.first.message).to include("Bookings staff")
    expect(AiAssistant::SubsystemBuild.count).to eq(0)
  end

  it "rejects an address the admin never typed" do
    outcome = run(input.merge("values" => [{ "label" => "Team", "value" => "Write to team@made-up.test" }]))

    expect(outcome.violations.map { |violation| [violation.code, violation.pointer] }).to eq([["subsystem.value_not_given", "/values/0/value"]])
    expect(outcome.violations.first.details).to eq("value" => "team@made-up.test")
  end

  it "rejects a brief that misses the scenarios" do
    expect(run(input.except("scenarios")).status).to eq("invalid")
  end

  it "refuses a second build while one is active in the conversation" do
    run

    outcome = run

    expect(outcome.violations.map { |violation| [violation.code, violation.resolution] }).to eq([["subsystem.build_active", "blocked"]])
    expect(AiAssistant::SubsystemBuild.count).to eq(1)
  end

  it "needs a conversation of this tenant" do
    expect(run(ctx: Operations::Context.new(customer: customer, actor: owner, channel: "assistant")).violations.map(&:code))
      .to eq(["subsystem.conversation_required"])

    foreign = create(:ai_assistant_conversation, customer: other, user: owner)
    ctx = Operations::Context.new(customer: customer, actor: owner, channel: "assistant", conversation: foreign)
    expect(run(ctx: ctx).violations.map(&:code)).to eq(["subsystem.conversation_required"])
  end

  it "checks sign-in against the workspace before building" do
    allow(AiAssistant::Subsystems::Preflight).to receive(:call).and_call_original
    people = [*input["people"], { "name" => "Member", "audience" => "member", "sign_in" => "self_signup" }]

    outcome = run(input.merge("people" => people))

    expect(AiAssistant::Subsystems::Preflight).to have_received(:call)
      .with(customer: customer, plan: AiAssistant::Subsystems::Preflight::Plan.new(logins: true, signup: true))
    expect(outcome.violations.map { |violation| [violation.code, violation.resolution] }).to eq([["subsystem.preflight_blocked", "blocked"]])
    expect(outcome.violations.first.message).to eq(I18n.t("ai_assistant.subsystems.preflight.logins_unavailable"))
  end

  it "starts a build for a tenant admin in their own conversation" do
    own = create(:ai_assistant_conversation, customer: customer, user: admin)
    say("Email bookings@club.test", in_conversation: own)

    outcome = run(ctx: Operations::Context.new(customer: customer, actor: admin, channel: "assistant", conversation: own))

    expect(outcome.status).to eq("succeeded"), outcome.violations.map(&:as_json).inspect
    expect(AiAssistant::SubsystemBuild.for_customer(customer.id).sole).to have_attributes(user: admin, conversation: own)
  end

  it "forbids a member and another tenant's admin" do
    [create(:user, :member, customer: customer), create(:user, :admin, customer: other)].each do |actor|
      ctx = Operations::Context.new(customer: customer, actor: actor, channel: "assistant", conversation: conversation)
      expect(run(ctx: ctx).status).to eq("forbidden")
    end
    expect(AiAssistant::SubsystemBuild.count).to eq(0)
  end

  it "replays a stored outcome for the same idempotency key" do
    ctx = Operations::Context.new(customer: customer, actor: owner, channel: "assistant", conversation: conversation,
                                  idempotency_key: "build-1")
    run(ctx: ctx)

    expect(run(ctx: ctx).replayed).to be(true)
    expect(AiAssistant::SubsystemBuild.count).to eq(1)
  end

  it "returns a dry_run plan without writing or enqueueing" do
    ctx = Operations::Context.new(customer: customer, actor: owner, channel: "assistant", conversation: conversation, dry_run: true)
    outcome = nil

    expect { outcome = run(ctx: ctx) }.not_to have_enqueued_job(AiAssistant::SubsystemBuildJob)
    expect(outcome.status).to eq("dry_run")
    expect(outcome.plan).to eq([{ "kind" => "subsystem_build", "action" => "started", "name" => "Venue Bookings" }])
    expect(AiAssistant::SubsystemBuild.count).to eq(0)
  end
end
