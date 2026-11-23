# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::SetPageProcessing do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:owner) { find_or_create_platform_owner }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:context) { Operations::Context.new(customer: customer, actor: admin, channel: "assistant") }
  let!(:page) { create(:page, customer: customer, action_key: "student_new", audience_admin: true) }
  let!(:processing) { create(:flowchart, :draft, customer: customer, name: "Save and notify") }
  let(:input) { { "page" => "student_new", "audience" => "admin", "processing" => "Save and notify" } }

  def run(payload = input, ctx: context)
    Operations::Activities::Execute.call(operation: "set_page_processing", input: payload, context: ctx)
  end

  it "sets the named processing on the page for a tenant admin" do
    outcome = run

    expect(outcome.status).to eq("succeeded"), outcome.violations.map(&:as_json).inspect
    expect(page.reload.flowchart).to eq(processing)
    expect(outcome.data).to eq("page" => "student_new", "audience" => "admin", "processing" => "Save and notify")
  end

  it "is offered to tenant admins and the platform owner alike" do
    [admin, owner].each do |actor|
      expect(described_class.available?(Operations::Context.new(customer: customer, actor: actor, channel: "assistant"))).to be(true)
    end
  end

  it "accepts the shared default by name" do
    page.update_column(:flowchart_id, processing.id)
    shared = Flowcharts::DefaultPageFlowchart.fetch

    outcome = run(input.merge("processing" => shared.name))

    expect(outcome.status).to eq("succeeded"), outcome.violations.map(&:as_json).inspect
    expect(page.reload.flowchart).to eq(shared)
  end

  it "refuses offline processing for a launched page in words any admin may read" do
    page.update_columns(launched: true)
    before = page.reload.flowchart_id

    outcome = run

    expect(outcome.violations.map(&:code)).to eq(["page.processing_refused"])
    expect(outcome.violations.first.message).to include(I18n.t("maint_core.errors.page_launch.submission_process_offline"))
    expect(outcome.violations.map(&:message).join).not_to match(/flowchart/i)
    expect(page.reload.flowchart_id).to eq(before)
  end

  it "gives the platform owner the detailed reasons" do
    owner_context = Operations::Context.new(customer: customer, actor: owner, channel: "assistant")
    result = Pages::Activities::BindFlowchart::Result.new(ok: false, page: page, errors: ["Detailed reason"], reasons: ["Plain reason"])
    allow(Pages::Activities::BindFlowchart).to receive(:call).and_return(result)

    owner_message = run(ctx: owner_context).violations.first.message
    admin_message = run.violations.first.message

    expect(owner_message).to include("Detailed reason")
    expect(admin_message).to include("Plain reason")
    expect(admin_message).not_to include("Detailed reason")
  end

  it "reports an unknown page and unknown processing" do
    outcome = run(input.merge("page" => "nope_new", "processing" => "Missing"))

    expect(outcome.violations.map { |violation| [violation.code, violation.pointer] })
      .to eq([["page.not_found", "/page"], ["processing.not_found", "/processing"]])
    expect(outcome.violations.map(&:message).join).not_to match(/flowchart/i)
  end

  it "never uses another customer's processing" do
    create(:flowchart, :launched_status, customer: other, name: "Foreign")

    expect(run(input.merge("processing" => "Foreign")).violations.map(&:code)).to eq(["processing.not_found"])
  end

  it "never changes another customer's page" do
    create(:page, customer: other, action_key: "other_new", audience_admin: true)

    expect(run(input.merge("page" => "other_new")).violations.map(&:code)).to eq(["page.not_found"])
  end

  it "forbids a member and another customer's admin" do
    before = page.reload.flowchart_id

    [create(:user, :member, customer: customer), create(:user, :admin, customer: other)].each do |actor|
      ctx = Operations::Context.new(customer: customer, actor: actor, channel: "assistant")
      expect(run(ctx: ctx).status).to eq("forbidden")
    end
    expect(page.reload.flowchart_id).to eq(before)
  end

  it "replays a stored outcome for the same idempotency key" do
    ctx = Operations::Context.new(customer: customer, actor: admin, channel: "assistant", idempotency_key: "set-page-1")
    run(ctx: ctx)

    expect(run(ctx: ctx).replayed).to be(true)
    expect(page.reload.flowchart).to eq(processing)
  end

  it "returns a dry_run plan without writing" do
    before = page.reload.flowchart_id
    outcome = run(ctx: Operations::Context.new(customer: customer, actor: admin, channel: "assistant", dry_run: true))

    expect(outcome.status).to eq("dry_run")
    expect(outcome.plan).to eq([{ "kind" => "page", "action" => "updated", "name" => page.name }])
    expect(page.reload.flowchart_id).to eq(before)
  end
end
