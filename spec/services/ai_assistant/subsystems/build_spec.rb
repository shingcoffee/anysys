# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Subsystems::Build do
  let(:customer) { create(:customer) }
  let(:owner) { find_or_create_platform_owner }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:user) { admin }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }
  let(:flowchart_word) { /flowchart|流程图/i }

  before do
    enable_ai_assistant!(customer)
    allow(AiAssistant::Stream).to receive(:broadcast_message)
    allow(AiAssistant::Stream).to receive(:broadcast_message_replace)
    say("Build venue bookings. Email the team at bookings@club.test.")
  end

  def say(body)
    create(:ai_assistant_message, conversation: conversation, customer: customer, role: "user", body: body)
  end

  def start(brief = venue_brief)
    ctx = Operations::Context.new(customer: customer, actor: user, channel: "assistant", conversation: conversation)
    outcome = Operations::Activities::Execute.call(operation: "start_subsystem_build", context: ctx, input: brief)
    expect(outcome.status).to eq("succeeded"), outcome.violations.map(&:as_json).inspect
    AiAssistant::SubsystemBuild.find(outcome.data["build"])
  end

  def step(id, action, config)
    { "id" => id, "type" => "process", "label" => action, "steps" => [{ "action" => action, "config" => config }] }
  end

  def apply(*extras)
    processes = [step("p1", "build_contract", { "contractClass" => "EntityEntryContract", "modelVariable" => "model" }),
                 step("p2", "validate_contract", {}), step("p3", "save_model", {})]
    extras.each_with_index { |extra, index| processes << step("p#{index + 4}", extra["action"], extra["config"]) }
    ids = ["start_1", *processes.map { |process| process["id"] }, "end_1"]
    { intent: "apply_flowchart", reply: "Writing it.", updates_confirmed: false,
      flowchart: { "name" => "Model chose this name",
                   "elements" => [{ "id" => "start_1", "type" => "start", "label" => "Start" }, *processes,
                                  { "id" => "end_1", "type" => "end", "label" => "End" }],
                   "connections" => ids.each_cons(2).map { |from, to| { "from" => from, "to" => to } } } }.to_json
  end

  def log_step = { "action" => "log", "config" => { "messageTemplate" => "New booking", "includeBacktrace" => false, "structured" => false } }

  def run(build, *texts)
    calls = []
    chat = lambda do |messages|
      calls << messages
      { outcome: :success, text: texts.shift, raw: {} }
    end
    described_class.call(build: build.reload, chat: chat)
    calls
  end

  def flows_json(flows = venue_flows) = flows.to_json
  def entities_json(input = venue_entities) = input.to_json
  def processing_name = "Record a booking: Booking details"
  def journey(key) = Journey.for_customer(customer.id).find_by!(key: key)
  def entity(name) = Entity.find_by!(customer_id: customer.id, name: name)
  def build_messages = conversation.messages.where(role: "assistant").order(:id)
  def page(id) = Page.find(id)

  it "designs the flows, then the entities, builds every step's page, writes and binds processing, launches and reports" do
    build = start

    calls = run(build, flows_json, entities_json, apply(log_step))

    expect(build.reload).to have_attributes(status: "finished", stage: "report")
    domain = EntityDomain.find_by_name(customer.id, "Venue Bookings")
    expect(%w[Venue Booking Guest].map { |name| EntityDomains::Memberships.domain_id_for(customer.id, entity(name).id) }).to all(eq(domain.id))

    flows_call, entities_call, processing_call = calls
    expect(flows_call.first[:content]).to include("You design the business flows", '"title": "Business flows"')
    expect(flows_call.last[:content]).to include('"Staff book a venue"')
    expect(entities_call.last[:content]).to include("### Booking", "lifecycle transitions: Requested -> Approved by admin; Requested -> Declined by admin",
                                                    "Its rows belong to a Booking")
    expect(processing_call.last[:content]).to include(%(named "#{processing_name}"), "Email the bookings team the venue and date.",
                                                      %(Next page: "Guests"), "- Bookings team email: bookings@club.test")

    recorded = journey("record_booking")
    expect(recorded).to be_launched
    steps = recorded.steps_definition.steps
    expect(steps.map { |row| [row.key, row.kind] }).to eq([%w[booking create], %w[guests relate], %w[finish finish]])
    expect(steps.second).to have_attributes(inputs: { "booking" => "booking" }, repeat: true, optional: true)
    pages = build.results.dig("journeys", "record_booking", "pages")
    booking_page = page(pages["booking"])
    expect(booking_page).to have_attributes(name: "Record a booking: Booking details", entity_id: entity("Booking").id)
    expect(booking_page.input_fields.map { |field| field["property_slug"] }).to eq(%w[venue booking_date])
    expect(booking_page.flowchart.name).to eq(processing_name)
    expect(page(pages["guests"]).page_inputs).to eq([{ "field" => "booking", "entity_id" => entity("Booking").id.to_s }])
    expect(page(pages["guests"]).success_message).to eq("Booking recorded.")

    reviewed = journey("review_booking")
    expect(reviewed).to be_launched
    record, review = reviewed.steps_definition.steps
    expect(record).to have_attributes(kind: "record", entity_id: entity("Booking").id.to_s, when: { "field" => "booking_status", "in" => ["Requested"] })
    expect(review).to have_attributes(kind: "update", record: "record")
    review_page = page(build.results.dig("journeys", "review_booking", "pages", "review"))
    expect(review_page.configuration_json.dig("form_settings", "modes")).to eq(%w[update])
    expect(Entities::Lifecycle.next_states(entity("Booking"), "booking_status", "Requested", audience: "admin")).to eq(%w[Approved Declined])

    report = build_messages.last.body
    expect(report).to include(
      I18n.t("ai_assistant.subsystems.report.entity_created", name: "Booking"),
      I18n.t("ai_assistant.subsystems.report.journey_launched", name: "Review a booking"),
      I18n.t("ai_assistant.subsystems.report.processing_bound", name: processing_name, page: booking_page.name),
      "Reminder emails before the booking"
    )
    expect(build_messages.map(&:body).join).not_to match(flowchart_word)
  end

  it "sends the flows' problems back to the model and builds the repaired flows" do
    broken = venue_flows.deep_dup
    broken["journeys"].second["steps"].first["status_choices"] = %w[Approved Cancelled]

    calls = run(start, flows_json(broken), flows_json, entities_json, apply(log_step))

    expect(calls.second.last[:content]).to include("Cancelled is not a state of Booking.")
    expect(journey("review_booking")).to be_launched
  end

  it "stops before building anything when the flows can't be repaired" do
    build = start

    run(build, "not json", "{}", flows_json(venue_flows.merge("journeys" => [])))

    expect(build.reload).to have_attributes(status: "failed", stage: "journeys")
    expect(build_messages.last.body).to eq(I18n.t("ai_assistant.subsystems.build.flows_failed", name: "Venue Bookings"))
    expect(Entity.where(customer_id: customer.id)).to be_empty
  end

  it "asks the admin once while designing the flows, then designs them with the answer" do
    build = start
    questions = { "questions" => [{ "prompt" => "Do guests need their own record?", "type" => "single", "options" => %w[Yes No] }] }

    run(build, questions.to_json)

    expect(build.reload).to have_attributes(status: "waiting_for_answers", stage: "journeys")
    expect(build.questions.map { |question| question["prompt"] }).to eq(["Do guests need their own record?"])
    expect(build_messages.last.metadata).to include("questions" => build.questions)

    answer = say("Do guests need their own record?\nYes")
    build.update!(status: "running", questions: [], answers: [{ "message_id" => answer.id, "questions" => build.questions }])
    calls = run(build, questions.to_json, flows_json, entities_json, apply(log_step))

    expect(calls.first.last[:content]).to include("Reply: Do guests need their own record?\nYes", "The admin can't be asked again.")
    expect(calls.second.last[:content]).to include("The admin can't be asked again.")
    expect(build.reload.status).to eq("finished")
  end

  it "sends gaps in the entities back to the model before writing any" do
    thin = venue_entities.deep_dup
    thin["entities"].second["attributes"].delete_at(1)

    calls = run(start, flows_json, entities_json(thin), entities_json, apply(log_step))

    expect(calls.third.last[:content]).to include("Booking: add the field Booking date.")
    expect(entity("Booking").property_schema_json.map { |attribute| attribute["name_slug"] }).to include("booking_date")
  end

  it "reuses an existing entity that covers the flows and reports it" do
    venue = create(:entity, customer: customer, name: "Venue", display_label: "Venue",
                            property_schema: [{ "name" => "Venue name", "name_slug" => "venue_name", "html_type" => "text", "type" => "String" }].to_json)
    input = venue_entities.deep_dup
    input["entities"].shift

    run(start, flows_json, entities_json(input), apply(log_step))

    expect(Entity.where(customer_id: customer.id, name: "Venue").sole).to eq(venue)
    expect(build_messages.last.body).to include(I18n.t("ai_assistant.subsystems.report.entity_reused", name: "Venue"))
  end

  it "gives the customer its own entity when a shared one of that name lacks what the flows need" do
    shared = create(:entity, :shared, name: "Booking", display_label: "Booking", property_schema: [].to_json)

    run(start, flows_json, entities_json, apply(log_step))

    expect(entity("Booking").property_schema_json.map { |attribute| attribute["name_slug"] }).to include("booking_status")
    expect(shared.reload.property_schema_json).to eq([])
    expect(journey("review_booking")).to be_launched
  end

  it "sends an entities reply that breaks the create_entity contract back to the model" do
    broken = venue_entities.deep_dup
    broken["entities"].first["attributes"] = nil

    calls = run(start, flows_json, entities_json(broken), entities_json, apply(log_step))

    expect(calls.third.last[:content]).to include("/entities/0/attributes")
    expect(journey("record_booking")).to be_launched
  end

  it "stops when an existing entity lacks what the flows need" do
    create(:entity, customer: customer, name: "Booking", display_label: "Booking", property_schema: [].to_json)
    build = start

    run(build, flows_json)

    expect(build.reload).to have_attributes(status: "failed", stage: "entities")
    expect(build_messages.last.body).to include(I18n.t("ai_assistant.subsystems.build.entity_gaps", name: "Booking"))
    expect(Journey.for_customer(customer.id)).to be_empty
  end

  context "for the platform owner" do
    let(:user) { owner }

    it "shows the flows and waits for approval before building, then builds" do
      build = start

      run(build, flows_json)

      expect(build.reload).to have_attributes(status: "waiting_for_answers", stage: "review")
      expect(build_messages.last.body).to include(I18n.t("ai_assistant.subsystems.review.intro", name: "Venue Bookings"), "**Record a booking**")
      expect(build.questions.sole).to include("prompt" => I18n.t("ai_assistant.subsystems.review.question"), "type" => "single")
      expect(Entity.where(customer_id: customer.id)).to be_empty

      answer = say("#{I18n.t('ai_assistant.subsystems.review.question')}\n#{I18n.t('ai_assistant.subsystems.review.approve')}")
      build.update!(status: "running", questions: [], answers: [{ "message_id" => answer.id, "questions" => build.questions }])
      run(build, entities_json, apply(log_step))

      expect(build.reload.status).to eq("finished")
      expect(journey("record_booking")).to be_launched
    end

    it "redesigns the flows with the owner's change and asks again" do
      build = start
      run(build, flows_json)
      answer = say("#{I18n.t('ai_assistant.subsystems.review.question')}\nDrop the guests step.")
      build.update!(status: "running", questions: [], answers: [{ "message_id" => answer.id, "questions" => build.questions }])
      changed = venue_flows.deep_dup
      changed["journeys"].first["steps"].pop

      calls = run(build, flows_json(changed))

      expect(calls.sole.last[:content]).to include("Change these flows as the platform owner asks\nDrop the guests step.", "Your earlier flows")
      expect(build.reload).to have_attributes(status: "waiting_for_answers", stage: "review")
      expect(build.results["flows"]).to eq(changed)
    end
  end

  it "stops at the next item once the build is cancelled" do
    build = start
    chat = lambda do |_messages|
      AiAssistant::SubsystemBuild.where(id: build.id).update_all(status: "cancelled")
      { outcome: :success, text: flows_json, raw: {} }
    end

    described_class.call(build: build.reload, chat: chat)

    expect(build.reload).to have_attributes(status: "cancelled", stage: "journeys")
    expect(build_messages).to be_empty
  end

  it "keeps no pages of a journey the worker died assembling, so the build runs again without building it twice" do
    build = start
    allow(AiAssistant::Subsystems::AssembleJourney).to receive(:call).and_wrap_original do |original, **args|
      original.call(**args).tap { raise "worker died" }
    end
    run(build, flows_json, entities_json)

    expect(build.reload).to have_attributes(status: "failed", stage: "pages")
    expect(build.results["journeys"]).to be_blank
    expect(Page.where(customer_id: customer.id)).to be_empty
    expect(Journey.for_customer(customer.id)).to be_empty

    allow(AiAssistant::Subsystems::AssembleJourney).to receive(:call).and_call_original
    build.update!(status: "running", results: build.results.except("error"))
    run(build, apply(log_step))

    expect(build.reload.status).to eq("finished")
    expect(Journey.for_customer(customer.id).pluck(:key)).to contain_exactly("record_booking", "review_booking")
    expect(Page.where(customer_id: customer.id).count).to eq(3)
  end

  it "rewrites the processing a worker died writing, rather than refusing its name, when the build runs again" do
    build = start
    allow(FlowchartDefinitions::Assistant::Processor).to receive(:call).and_wrap_original do |original, **args|
      original.call(**args).tap { raise "worker died" }
    end
    run(build, flows_json, entities_json, apply(log_step))
    expect(build.reload.results.dig("processing", processing_name)).to eq("writing" => true)
    written = Flowchart.find_by!(customer_id: customer.id, name: processing_name)

    allow(FlowchartDefinitions::Assistant::Processor).to receive(:call).and_call_original
    build.update!(status: "running", results: build.results.except("error"))
    run(build, apply(log_step))

    expect(build.reload.status).to eq("finished")
    expect(build.results.dig("processing", processing_name)).to include("status" => "created", "flowchart_id" => written.id, "bound" => true)
    expect(Flowchart.where(customer_id: customer.id, name: processing_name).sole).to eq(written)
  end

  it "stops a build whose user may no longer build here" do
    build = start
    build.update_column(:user_id, create(:user, :member, customer: customer).id)

    run(build)

    expect(build.reload).to have_attributes(status: "failed")
    expect(build.results["error"]).to eq("unauthorized")
    expect(build_messages.last.body).to eq(I18n.t("ai_assistant.subsystems.build.unauthorized", name: "Venue Bookings"))
  end

  it "reports an unexpected failure and keeps what it built" do
    build = start
    allow(Pages::Activities::BindFlowchart).to receive(:call).and_raise(RuntimeError, "boom")

    run(build, flows_json, entities_json, apply(log_step))

    expect(build.reload).to have_attributes(status: "failed", stage: "binding")
    expect(build_messages.last.body).to eq(I18n.t("ai_assistant.subsystems.build.unexpected", name: "Venue Bookings"))
    expect(entity("Booking")).to be_present
  end

  it "reports a refused page change with the reasons any admin may read" do
    build = start
    refused = Pages::Activities::BindFlowchart::Result.new(ok: false, page: nil, errors: ["Flowchart step detail"], reasons: ["Plain reason"])
    allow(Pages::Activities::BindFlowchart).to receive(:call).and_return(refused)

    run(build, flows_json, entities_json, apply(log_step))

    expect(build_messages.last.body).to include("Plain reason")
    expect(build_messages.last.body).not_to include("Flowchart step detail")
    expect(journey("record_booking")).to be_draft
  end

  it "asks and reports in Chinese without saying flowchart" do
    I18n.with_locale(:"zh-CN") do
      build = start
      run(build, flows_json, entities_json, apply(log_step))

      expect(build.reload.status).to eq("finished")
      expect(build_messages.last.body).to include(I18n.t("ai_assistant.subsystems.report.title", name: "Venue Bookings"))
      expect(build_messages.map(&:body).join).not_to match(flowchart_word)
    end
  end
end
