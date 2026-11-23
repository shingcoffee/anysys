# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::StateMachine do
  let(:transitions) { { "draft" => "submitted", "submitted" => "approved, rejected", "*" => "cancelled" } }

  def transition(ctx, **opts)
    described_class.transition(
      ctx,
      current: opts.fetch(:current),
      target: opts.fetch(:target),
      transitions: opts.fetch(:transitions, transitions),
      initial_state: opts.fetch(:initial_state, ""),
      allow_same: opts.fetch(:allow_same, false),
      guard: opts.fetch(:guard, true),
      on_invalid: opts.fetch(:on_invalid, "fail"),
      record: opts[:record],
      state_field: opts[:state_field],
      timestamp_field: opts[:timestamp_field],
      variable: opts[:variable]
    )
  end

  describe ".read_field" do
    it "reads a hash key, an EntityEntry field, or nil" do
      expect(described_class.read_field({ "status" => "draft" }, "status")).to eq("draft")
      expect(described_class.read_field({ status: "open" }, "status")).to eq("open")
      expect(described_class.read_field(nil, "status")).to be_nil
    end
  end

  describe ".transition" do
    it "allows a mapped transition and a wildcard from-state" do
      ctx = { errors: [] }
      expect(transition(ctx, current: "draft", target: "submitted")).to include(
        state: "submitted", previous_state: "draft", transitioned: true
      )
      expect(transition(ctx, current: "open", target: "cancelled")).to include(
        state: "cancelled", transitioned: true
      )
    end

    it "uses initial_state when current is blank" do
      ctx = { errors: [] }
      expect(transition(ctx, current: nil, target: "submitted", initial_state: "draft")).to include(
        state: "submitted", previous_state: "draft", transitioned: true
      )
    end

    it "treats the same state as a successful no-op when allowed" do
      ctx = { errors: [] }
      expect(transition(ctx, current: "draft", target: "draft", allow_same: true)).to include(
        state: "draft", previous_state: "draft", transitioned: false
      )
    end

    it "fails an invalid transition and interpolates from/to" do
      ctx = { errors: [] }
      expect(transition(ctx, current: "draft", target: "approved")).to eq(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.transition_state.invalid_transition",
                                         from: "draft", to: "approved")])
      expect(ctx[:error_details].last["code"]).to eq("transition_state.invalid_transition")
    end

    it "leaves the state untouched on skip" do
      ctx = { errors: [] }
      expect(transition(ctx, current: "draft", target: "approved", on_invalid: "skip")).to include(
        state: "draft", transitioned: false
      )
      expect(ctx[:errors]).to eq([])
    end

    it "fails when the guard is false" do
      ctx = { errors: [] }
      expect(transition(ctx, current: "draft", target: "submitted", guard: false)).to eq(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.transition_state.guard_failed",
                                         from: "draft", to: "submitted")])
    end

    it "fails when a record source has no record" do
      ctx = { errors: [] }
      expect(transition(ctx, current: "draft", target: "submitted", record: nil, state_field: "status")).to eq(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.transition_state.missing_record")])
    end

    it "writes a record field without saving and stamps a timestamp" do
      customer = create(:customer)
      entity = create(:entity, customer: customer, property_schema: [
        { "name" => "Status", "name_slug" => "status", "data_type" => "string" },
        { "name" => "Changed", "name_slug" => "status_changed_at", "data_type" => "datetime" }
      ].to_json)
      entry = create(:entity_entry, :with_data, entity: entity, customer: customer,
                     entry_data: { "status" => "draft" })
      model = FlowchartRuntime::Entries.find_by({ bound_entity: entity, customer_id: customer.id }, "id" => entry.id)
      ctx = { bound_entity: entity, customer_id: customer.id, errors: [] }
      stamp = Time.zone.local(2026, 11, 16, 12)

      travel_to stamp do
        result = transition(ctx, current: "draft", target: "submitted", record: model,
                                state_field: "status", timestamp_field: "status_changed_at")
        expect(result[:transitioned]).to be(true)
      end
      expect(model.status).to eq("submitted")
      expect(model.status_changed_at).to eq(stamp.utc.iso8601(3))
      expect(entry.reload.data_json["status"]).to eq("draft")
    end

    it "raises StateMachine::Error when the state field is not an attribute of the record" do
      customer = create(:customer)
      entity = create(:entity, customer: customer, property_schema: [
        { "name" => "Status", "name_slug" => "status", "data_type" => "string" }
      ].to_json)
      entry = create(:entity_entry, :with_data, entity: entity, customer: customer,
                     entry_data: { "status" => "draft" })
      model = FlowchartRuntime::Entries.find_by({ bound_entity: entity, customer_id: customer.id }, "id" => entry.id)
      ctx = { bound_entity: entity, customer_id: customer.id, errors: [] }

      expect do
        transition(ctx, current: "draft", target: "submitted", record: model, state_field: "phase")
      end.to raise_error(described_class::Error, /phase/)
    end

    it "writes a ctx variable when the transition happens" do
      ctx = { status: "draft", errors: [] }
      expect(transition(ctx, current: "draft", target: "submitted", variable: :status)[:transitioned]).to be(true)
      expect(ctx[:status]).to eq("submitted")
    end

    it "does not write a ctx variable on skip" do
      ctx = { status: "draft", errors: [] }
      transition(ctx, current: "draft", target: "approved", on_invalid: "skip", variable: :status)
      expect(ctx[:status]).to eq("draft")
    end

    context "with no map on a record whose state field declares a lifecycle" do
      let(:customer) { create(:customer) }
      let(:entity) do
        create(:entity, customer: customer, property_schema: [
          { "name" => "Status", "name_slug" => "status", "html_type" => "select",
            "config" => { "source" => "manual", "options" => [
              { "label" => "Draft", "value" => "draft", "default" => true },
              { "label" => "Submitted", "value" => "submitted" }, { "label" => "Approved", "value" => "approved" }
            ] },
            "lifecycle" => { "transitions" => [{ "from" => "draft", "to" => "submitted", "by" => ["member"] },
                                               { "from" => "submitted", "to" => "approved", "by" => ["admin"] }] } },
          { "name" => "Title", "name_slug" => "title", "html_type" => "text" }
        ].to_json)
      end
      let(:ctx) { { bound_entity: entity, customer_id: customer.id, errors: [] } }

      def model(data)
        entry = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: data)
        FlowchartRuntime::Entries.find_by({ bound_entity: entity, customer_id: customer.id }, "id" => entry.id)
      end

      it "allows any transition the lifecycle lists, whoever causes it" do
        record = model("status" => "submitted")

        expect(transition(ctx, current: "submitted", target: "approved", transitions: {}, record: record, state_field: "status"))
          .to include(state: "approved", previous_state: "submitted", transitioned: true)
        expect(record.status).to eq("approved")
      end

      it "starts a blank state at the lifecycle's initial state" do
        record = model("title" => "New")

        expect(transition(ctx, current: nil, target: "submitted", transitions: {}, record: record, state_field: "status"))
          .to include(state: "submitted", previous_state: "draft", transitioned: true)
      end

      it "refuses a change the lifecycle does not list" do
        record = model("status" => "draft")

        expect(transition(ctx, current: "draft", target: "approved", transitions: {}, record: record, state_field: "status")).to eq(false)
        expect(ctx[:error_details].last["code"]).to eq("transition_state.invalid_transition")
        expect(record.status).to eq("draft")
      end

      it "keeps a declared map over the lifecycle, and has nothing to follow on a field without one" do
        record = model("status" => "draft")
        expect(transition(ctx, current: "draft", target: "approved", transitions: { "draft" => "approved" },
                               record: record, state_field: "status")).to include(transitioned: true)

        expect(transition(ctx, current: "", target: "x", transitions: {}, record: model("title" => "T"), state_field: "title")).to eq(false)
      end
    end
  end
end
