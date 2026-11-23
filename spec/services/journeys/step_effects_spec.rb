# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::StepEffects do
  let(:customer) { create(:customer) }
  let(:status) do
    { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "select",
      "config" => { "source" => "manual", "options" => [
        { "label" => "Requested", "value" => "requested", "default" => true },
        { "label" => "Approved", "value" => "approved" }, { "label" => "Declined", "value" => "declined" },
        { "label" => "Paid", "value" => "paid" }
      ] },
      "lifecycle" => { "transitions" => [
        { "from" => "requested", "to" => "approved", "by" => %w[admin] },
        { "from" => "requested", "to" => "declined", "by" => %w[admin] },
        { "from" => "approved", "to" => "paid", "by" => %w[system] }
      ] } }
  end
  let(:booking) do
    create(:entity, customer: customer, name: "Booking", display_label: "Booking", property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" },
      { "name" => "Total", "name_slug" => "total", "type" => "Decimal", "html_type" => "number" },
      status
    ].to_json)
  end

  def page_with(fields: [], modes: %w[create], **attributes)
    Current.set(customer: customer) do
      create(:page, customer: customer, entity: booking, launched: true, **attributes, configuration: {
        form_settings: { modes: modes },
        metadata: { entity_id: booking.id, entity_name: booking.name },
        pages: [{ "id" => "page_1", "fields" => fields.map { |slug| { "id" => "f_#{slug}", "property_slug" => slug, "source" => "entity", "html_type" => "text" } } }]
      }.to_json)
    end
  end

  def summary(page) = described_class.new(customer: customer).for(page)

  # The summary reads the configuration only, so the sketched step configs are never compiled.
  def bind_processing(page, steps)
    allow(ActivityGenerator).to receive(:new).and_return(instance_double(ActivityGenerator, generate: ""))
    bind_page_flowchart(page, steps: steps, body: "true")
  end
  def t(key, **vars) = I18n.t("journeys.admin.effects.#{key}", **vars)
  def state(value) = described_class::State.new(entity_id: booking.id.to_s, field: "status", value: value)

  it "reads the default processing as a plain save, with the state a new record starts in" do
    result = summary(page_with(fields: %w[title]))

    expect(result).to be_processed
    expect(result.lines).to eq([t(:saves_only)])
    expect(result.creating).to eq([t(:starts_in, entity: "Booking", field: "Status", state: "Requested")])
    expect(result.initials).to eq([state("requested")])
    expect(result.left_in(creates: true)).to eq([state("requested")])
    expect(result.left_in(creates: false)).to eq([])
  end

  it "describes each side effect of the processing in the order it runs, and the steps it may leave out" do
    page = page_with(fields: %w[title])
    bind_processing(page, [
      { "action" => "fail_with_error", "config" => { "message" => { "en" => "No" } } },
      { "action" => "set_record_fields", "config" => { "assignments" => [{ "key" => "total", "value" => "10" },
                                                                         { "key" => "status", "value" => "\"approved\"" }] } },
      { "action" => "transition_state", "config" => { "stateField" => "status", "targetSource" => "variable", "targetVariable" => "next" } },
      { "action" => "send_template_email", "config" => {} },
      { "action" => "send_email", "config" => {} },
      { "action" => "related_record", "config" => { "operation" => "find" } },
      { "action" => "child_records", "config" => { "operation" => "create" } },
      { "action" => "update_model", "config" => { "modelVariable" => "related_record", "assignments" => [] } },
      { "action" => "skip_journey_steps", "config" => { "steps" => %w[catering notes] } },
      { "action" => "request_payment", "config" => { "paidFields" => [{ "key" => "status", "value" => "paid" }] } },
      { "action" => "assign_value", "config" => {} }
    ])

    result = summary(page.reload)

    expect(result.flowchart).to eq(page.flowchart)
    expect(result.lines).to eq([
      t(:refuses), t(:sets, fields: "Total"), t(:moves, field: "Status", state: "Approved"),
      t(:moves_computed, field: "Status"), t(:email), t(:other_records),
      t(:skips, steps: "catering#{t('separators.and')}notes"), t(:payment),
      t(:paid_move, field: "Status", state: "Paid"), t(:saves)
    ])
    expect(result.states).to eq([state("approved"), state("paid")])
    expect(result.skips).to eq(%w[catering notes])
    expect(result.creating).to eq([])
  end

  it "says who picks the status on the form, and what the hand-off and record-level actions do" do
    page = page_with(fields: %w[title status], modes: %w[update])
    bind_processing(page, [
      { "action" => "hand_off_to_module", "config" => { "moduleKey" => "nowhere" } },
      { "action" => "destroy_model", "config" => { "mode" => "archive" } },
      { "action" => "register_member", "config" => {} },
      { "action" => "transition_state", "config" => { "stateSource" => "variable" } }
    ])

    result = summary(page.reload)

    expect(result.lines).to eq([
      t(:hand_off, module: "nowhere"), t(:archives), t(:member_account), t(:other_records), t(:saves),
      t(:chooses, field: "Status", states: "Approved#{t('separators.or')}Declined")
    ])
    expect(result.states).to eq([state("approved"), state("declined")])
    expect(result.initials).to eq([])
  end

  it "says a page with no processing, or processing that is offline, refuses submissions" do
    unbound = page_with
    unbound.update_column(:flowchart_id, nil)
    offline = page_with
    offline.flowchart.update_column(:status, Flowchart.statuses[:draft])

    expect(summary(unbound.reload)).to have_attributes(processed?: false, lines: [t(:unprocessed)], states: [])
    expect(summary(offline.reload).lines).to eq([t(:offline), t(:saves)])
  end

  it "reads a shared processing through the customer's override" do
    allow(ActivityGenerator).to receive(:new).and_return(instance_double(ActivityGenerator, generate: ""))
    shared = create_page_flowchart(customer: nil, steps: [{ "action" => "send_sms", "config" => {} }], body: "true")
    page = page_with
    page.update_column(:flowchart_id, shared.id)
    allow(FlowchartRuntime::RuntimeFlowchart).to receive(:new).and_wrap_original do |original, record|
      expect(Current.customer).to eq(customer)
      original.call(record)
    end

    expect(summary(page.reload).lines).to eq([t(:sms), t(:saves)])
  end

  it "says processing it can't read can't be read, and passes over malformed elements" do
    page = page_with(fields: %w[title])
    allow(FlowchartRuntime::RuntimeFlowchart).to receive(:new).and_raise(JSON::ParserError)
    expect(summary(page)).to have_attributes(flowchart: page.flowchart, lines: [t(:unreadable)], states: [], skips: [])

    reading = lambda do |configuration|
      allow(FlowchartRuntime::RuntimeFlowchart).to receive(:new).and_wrap_original do |original, record|
        original.call(record).tap { |flowchart| allow(flowchart).to receive(:configuration_json).and_return(configuration) }
      end
      summary(page).lines
    end
    junk = ["x", { "properties" => "x" }, { "properties" => { "steps" => ["x", { "action" => "send_email" }] } }]
    expect(reading.call({ "elements" => junk })).to eq([t(:email)])
    expect(reading.call([1])).to eq([t(:nothing)])
  end

  it "joins lists in the current locale" do
    expect(described_class.join(%w[A])).to eq("A")
    expect(described_class.join(%w[A B C], last: :or)).to eq("A, B or C")
    I18n.with_locale(:"zh-CN") { expect(described_class.join(%w[甲 乙 丙])).to eq("甲、乙和丙") }
  end
end
