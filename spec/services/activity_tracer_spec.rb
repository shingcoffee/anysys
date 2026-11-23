# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityTracer do
  let(:entity) { create(:entity) }
  let(:flowchart) { create(:flowchart, :simple) }

  describe '#call' do
    context 'with a valid flowchart' do
      let(:result) { described_class.new(flowchart).call({}) }

      it 'returns a Result struct' do
        expect(result).to be_a(ActivityTracer::Result)
      end

      it 'executes the activity successfully' do
        expect(result.error).to be_nil
        expect(result.truncated).to be false
      end

      it 'includes trace output' do
        expect(result.trace).to be_present
      end

      it 'includes trace nodes for visualization' do
        expect(result.trace_nodes).to be_an(Array)
      end

      it 'tags step trace nodes with the originating canvas element id' do
        # The UI highlights canvas elements by this stable id rather than by a
        # lossy label re-normalization (which mismatches on duplicate / numeric
        # / reserved-word labels). The :simple flowchart's process element is
        # 'process_1'.
        element_ids = flowchart.elements.map { |e| e["id"] }
        tagged = result.trace_nodes.select { |n| n[:element_id].present? }

        expect(tagged).not_to be_empty
        # Every supplied element_id is a real canvas element id…
        expect(tagged.map { |n| n[:element_id] }).to all(be_in(element_ids))
        # …and the process step maps back to the process element specifically.
        expect(result.trace_nodes.map { |n| n[:element_id] }).to include('process_1')
      end
    end

    context 'with no activity code' do
      let(:flowchart_without_activity) do
        f = create(:flowchart, :empty)
        f.update_column(:activity, nil)
        f
      end

      it 'returns an error result' do
        result = described_class.new(flowchart_without_activity).call({})

        expect(result.success?).to be false
        expect(result.error).to eq('No activity code generated')
      end
    end

    context 'with invalid activity code' do
      let(:flowchart_with_bad_code) do
        f = create(:flowchart, :simple)
        f.update_column(:activity, 'invalid ruby code def end')
        f
      end

      it 'returns an error result' do
        result = described_class.new(flowchart_with_bad_code).call({})

        expect(result.success?).to be false
        expect(result.error).to include('Failed to build activity class')
      end
    end

    context 'with input parameters' do
      it 'passes input to the activity' do
        result = described_class.new(flowchart).call(name: 'Test', value: 42)

        expect(result.ctx).to include(:name, :value)
      end

      it 'seeds the running flowchart id over any posted value' do
        result = described_class.new(flowchart).call(name: 'Test', flowchart_id: 999_999)

        expect(result.ctx[:flowchart_id]).to eq(flowchart.id)
      end
    end

    context 'with a public-form params.amount decision' do
      # Public submissions seed ctx[:params] as a string-keyed Hash
      # (Pages::FormParams.permit). The admin test runner deep-symbolizes.
      # ActivityTracer#call must normalize so ctx.dig(:params, :amount) works
      # for both, and ConditionInput.compare must coerce numeric strings.
      let(:amount_decision_flowchart) do
        config = {
          "elements" => [
            { "id" => "s1", "type" => "start", "x" => 100, "y" => 50, "width" => 100, "height" => 45, "label" => "Start", "properties" => { "inputs" => [], "outputs" => [] } },
            {
              "id" => "d1", "type" => "decision", "x" => 100, "y" => 150, "width" => 100, "height" => 45, "label" => "Check amount",
              "properties" => {
                "routeBy" => "condition",
                "condition" => {
                  "type" => "group",
                  "joins" => [],
                  "conditions" => [
                    { "kind" => "field", "leftOperand" => "ctx.params.amount", "operator" => ">", "rightOperand" => "100" }
                  ]
                }
              }
            },
            {
              "id" => "a1", "type" => "process", "x" => 220, "y" => 250, "width" => 100, "height" => 45, "label" => "High value",
              "properties" => {
                "steps" => [{
                  "action" => "assign_value",
                  "config" => { "resultVar" => "high_value", "valueType" => "string", "stringValue" => "taken" }
                }],
                "inputs" => [],
                "outputs" => []
              }
            },
            {
              "id" => "b1", "type" => "process", "x" => 20, "y" => 250, "width" => 100, "height" => 45, "label" => "Low value",
              "properties" => {
                "steps" => [{
                  "action" => "assign_value",
                  "config" => { "resultVar" => "low_value", "valueType" => "string", "stringValue" => "taken" }
                }],
                "inputs" => [],
                "outputs" => []
              }
            },
            { "id" => "e1", "type" => "end", "x" => 100, "y" => 350, "width" => 100, "height" => 45, "label" => "End", "properties" => {} }
          ],
          "connections" => [
            { "id" => "c1", "from" => "s1", "to" => "d1" },
            { "id" => "c2", "from" => "d1", "to" => "a1", "label" => "Yes", "matchValue" => "true" },
            { "id" => "c3", "from" => "d1", "to" => "b1", "label" => "No", "matchValue" => "false" },
            { "id" => "c4", "from" => "a1", "to" => "e1" },
            { "id" => "c5", "from" => "b1", "to" => "e1" }
          ],
          "metadata" => { "canvas" => { "width" => 1200, "height" => 800 }, "created_at" => Time.current.iso8601 }
        }
        create(:flowchart, configuration: config.to_json)
      end

      it "takes the > 100 branch for string-keyed public params amount=150" do
        result = described_class.new(amount_decision_flowchart).call(params: { "amount" => "150" })

        expect(result.error).to be_nil
        expect(result.success?).to be true
        expect(result.ctx[:params]).to be_a(ActiveSupport::HashWithIndifferentAccess)
        expect(result.ctx[:high_value]).to eq("taken")
        expect(result.ctx[:low_value]).to be_nil
      end

      it "takes the other branch for string-keyed public params amount=50" do
        result = described_class.new(amount_decision_flowchart).call(params: { "amount" => "50" })

        expect(result.error).to be_nil
        expect(result.success?).to be true
        expect(result.ctx[:params]).to be_a(ActiveSupport::HashWithIndifferentAccess)
        expect(result.ctx[:low_value]).to eq("taken")
        expect(result.ctx[:high_value]).to be_nil
      end

      it "lists only executed nodes and the branch taken" do
        result = described_class.new(amount_decision_flowchart).call(params: { "amount" => "150" })

        expect(result.error).to be_nil
        ids = result.trace_nodes.map { |n| n[:id] }
        expect(ids).to include("Start.default", "check_amount", "high_value")
        expect(ids).not_to include("low_value", "collect_errors")
        expect(ids.count { |id| id.to_s.start_with?("End.") }).to eq(1)

        decision = result.trace_nodes.find { |n| n[:id] == "check_amount" }
        expect(decision[:status]).to eq("success")
        expect(decision[:branch]).to eq("Yes")
        expect(decision[:element_id]).to eq("d1")
        expect(decision[:label]).to eq("Check amount")

        start = result.trace_nodes.find { |n| n[:id] == "Start.default" }
        expect(start[:element_id]).to eq("s1")
        expect(start[:label]).to eq(I18n.t("flowchart_elements.trace.start"))

        finish = result.trace_nodes.find { |n| n[:id].to_s.start_with?("End.") }
        expect(finish[:element_id]).to eq("e1")
        expect(finish[:label]).to eq("End")
        expect(finish[:status]).to eq("success")
      end
    end

    context "with a failing contract run" do
      let(:validated_entity) do
        create(:entity, property_schema: [
          { "name" => "Name", "name_slug" => "name", "type" => "String", "validators" => [{ "type" => "presence" }] }
        ].to_json)
      end
      let(:create_flowchart) do
        fc = Flowchart.new_with_defaults(
          name: "Create Validated",
          customer: validated_entity.customer,
          template: "page_record"
        )
        fc.save!
        fc
      end

      it "ends with a failure End node and omits collect_errors" do
        record = EntityEntry.build_for(validated_entity).new(
          entity: validated_entity, customer_id: validated_entity.customer_id
        )
        result = described_class.new(create_flowchart).call(
          params: {},
          customer_id: validated_entity.customer_id,
          bound_entity: validated_entity,
          audience: :admin,
          model: record,
          page_record: record
        )

        expect(result.success?).to be false
        expect(result.error).to be_nil
        ids = result.trace_nodes.map { |n| n[:id] }
        expect(ids).to include("Start.default", "validate")
        expect(ids).not_to include("collect_errors", "save_model")

        finish = result.trace_nodes.find { |n| n[:id].to_s.start_with?("End.") }
        expect(finish).to be_present
        expect(finish[:id]).to eq("End.failure")
        expect(finish[:element_id]).to be_nil
        expect(finish[:label]).to eq(I18n.t("flowchart_elements.trace.failure"))
        expect(finish[:status]).to eq("failure")
      end
    end

    context "when a step raises" do
      let(:raising_flowchart) do
        config = {
          "elements" => [
            { "id" => "start_1", "type" => "start", "x" => 150, "y" => 100, "width" => 100, "height" => 45, "label" => "Begin", "properties" => { "inputs" => [], "outputs" => [] } },
            { "id" => "boom_1", "type" => "process", "x" => 150, "y" => 200, "width" => 100, "height" => 45, "label" => "Boom Step", "properties" => { "steps" => [], "inputs" => [], "outputs" => [] } },
            { "id" => "end_1", "type" => "end", "x" => 150, "y" => 300, "width" => 100, "height" => 45, "label" => "End", "properties" => {} }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "start_1", "to" => "boom_1" },
            { "id" => "conn_2", "from" => "boom_1", "to" => "end_1" }
          ],
          "metadata" => { "canvas" => { "width" => 1200, "height" => 800 }, "created_at" => Time.current.iso8601 }
        }
        f = create(:flowchart, configuration: config.to_json)
        patched = f.activity.sub(
          /def boom_step\(ctx, \*\*\)\n    true/,
          "def boom_step(ctx, **)\n    raise %{boom-from-step}"
        )
        f.update_column(:activity, patched)
        f
      end

      it "yields partial nodes with the failing node marked failure and keeps error" do
        result = described_class.new(raising_flowchart).call({})

        expect(result.error).to eq(I18n.t("flowchart_elements.trace.errors.execution_failed"))
        expect(result.error).not_to include("boom-from-step")
        expect(result.trace_nodes).not_to be_empty
        expect(result.trace_nodes.map { |n| n[:id] }).not_to include("collect_errors")

        failing = result.trace_nodes.find { |n| n[:id] == "boom_step" }
        expect(failing).to be_present
        expect(failing[:status]).to eq("failure")
        expect(failing[:element_id]).to eq("boom_1")
      end
    end

    it "does not print the Trailblazer WTF tree to stdout" do
      expect { described_class.new(flowchart).call({}) }.not_to output.to_stdout
    end

    context "when trace: false" do
      it "invokes the activity without Trailblazer::Developer::Trace and returns an empty trace" do
        expect(Trailblazer::Developer::Trace).not_to receive(:invoke)

        result = described_class.new(flowchart).call({}, trace: false)

        expect(result.error).to be_nil
        expect(result.success?).to be true
        expect(result.timeout?).to be false
        expect(result.trace).to be_nil
        expect(result.trace_nodes).to eq([])
        expect(result.queries).to eq([])
        expect(result.ctx).to be_a(Hash)
      end

      it "still reports a raising step as an error result without trace nodes" do
        config = {
          "elements" => [
            { "id" => "start_1", "type" => "start", "x" => 150, "y" => 100, "width" => 100, "height" => 45, "label" => "Begin", "properties" => { "inputs" => [], "outputs" => [] } },
            { "id" => "boom_1", "type" => "process", "x" => 150, "y" => 200, "width" => 100, "height" => 45, "label" => "Boom Step", "properties" => { "steps" => [], "inputs" => [], "outputs" => [] } },
            { "id" => "end_1", "type" => "end", "x" => 150, "y" => 300, "width" => 100, "height" => 45, "label" => "End", "properties" => {} }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "start_1", "to" => "boom_1" },
            { "id" => "conn_2", "from" => "boom_1", "to" => "end_1" }
          ],
          "metadata" => { "canvas" => { "width" => 1200, "height" => 800 }, "created_at" => Time.current.iso8601 }
        }
        f = create(:flowchart, configuration: config.to_json)
        f.update_column(:activity, f.activity.sub(
          /def boom_step\(ctx, \*\*\)\n    true/,
          "def boom_step(ctx, **)\n    raise %{boom-from-step}"
        ))

        expect(Trailblazer::Developer::Trace).not_to receive(:invoke)
        result = described_class.new(f).call({}, trace: false)

        expect(result.success?).to be false
        expect(result.error).to eq(I18n.t("flowchart_elements.trace.errors.execution_failed"))
        expect(result.error).not_to include("boom-from-step")
        expect(result.trace).to be_nil
        expect(result.trace_nodes).to eq([])
        expect(result.queries).to eq([])
      end

      it "returns the timeout failure without a trace when the untraced run exceeds the limit" do
        stub_const("ActivityTracer::EXECUTION_TIMEOUT_SECONDS", 0.1)
        f = create(:flowchart, :simple)
        f.update_column(:activity, f.activity.sub(
          /def process\(ctx, \*\*\)\n    true/,
          "def process(ctx, **)\n    sleep 0.5\n    true"
        ))

        expect(Trailblazer::Developer::Trace).not_to receive(:invoke)
        result = described_class.new(f).call({}, trace: false)

        expect(result.success?).to be false
        expect(result.timeout?).to be true
        expect(result.error).to eq(
          I18n.t("flowchart_elements.trace.errors.timed_out", seconds: ActivityTracer::EXECUTION_TIMEOUT_SECONDS)
        )
        expect(result.trace).to be_nil
        expect(result.trace_nodes).to eq([])
        expect(result.queries).to eq([])
      end
    end

    context "SQL query logging" do
      it "captures queries in result" do
        result = described_class.new(flowchart).call({})

        expect(result).to respond_to(:queries)
        expect(result.queries).to be_an(Array)
      end
    end

    context "execution timeout" do
      it "returns a timeout result when execution exceeds the limit" do
        stub_const("ActivityTracer::EXECUTION_TIMEOUT_SECONDS", 0.1)
        allow(Trailblazer::Developer::Trace).to receive(:invoke) { sleep 0.5 }

        result = described_class.new(flowchart).call({})

        expect(result.success?).to be false
        expect(result.timeout?).to be true
        expect(result.error).to eq(
          I18n.t("flowchart_elements.trace.errors.timed_out", seconds: ActivityTracer::EXECUTION_TIMEOUT_SECONDS)
        )
        expect(result.trace_nodes).to eq([])
        expect(result.queries).to eq([])
      end

      it "reports timeout? false on a successful run" do
        result = described_class.new(flowchart).call({})

        expect(result.error).to be_nil
        expect(result.timeout?).to be false
      end

      it "reports timeout? false on an ordinary error result" do
        f = create(:flowchart, :empty)
        f.update_column(:activity, nil)

        result = described_class.new(f).call({})

        expect(result.success?).to be false
        expect(result.timeout?).to be false
      end
    end

    context "per-step ctx snapshots (best-effort)" do
      # Snapshot extraction is BY DESIGN best-effort: each trace node either
      # carries a sanitized Hash under :ctx_snapshot or omits the key entirely.
      # Extraction failures must never fail the run or degrade the base shape.
      it "never raises and keeps the base node shape, with ctx_snapshot absent or a Hash" do
        result = described_class.new(flowchart).call(name: 'Test')

        expect(result.error).to be_nil
        expect(result.trace_nodes).not_to be_empty
        result.trace_nodes.each do |node|
          expect(node).to include(:id, :element_id, :label, :status, :signal)
          expect(node[:ctx_snapshot]).to be_a(Hash) if node.key?(:ctx_snapshot)
        end
      end

      it "redacts secret-bearing keys in per-step snapshots" do
        result = described_class.new(flowchart).call(api_token: "supersecret-123", name: "Test")

        expect(result.error).to be_nil
        snapshots = result.trace_nodes.filter_map { |n| n[:ctx_snapshot] }
        expect(snapshots).not_to be_empty

        token_entries = snapshots.flat_map { |s| s.select { |k, _| k.to_s.match?(/api_token/i) }.values }
        expect(token_entries).not_to be_empty
        expect(token_entries).to all(eq("[REDACTED]"))
        expect(snapshots.inspect).not_to include("supersecret-123")
      end

      it "survives a snapshot extraction failure without dropping the node" do
        allow(Trailblazer::Developer::Trace::Snapshot)
          .to receive(:snapshot_ctx_for).and_raise(RuntimeError, "boom")

        result = described_class.new(flowchart).call({})

        expect(result.error).to be_nil
        expect(result.trace_nodes).not_to be_empty
        expect(result.trace_nodes).to all(satisfy { |n| !n.key?(:ctx_snapshot) })
      end
    end
  end

  describe "#redact_sensitive_keys (snapshot secret redaction helper)" do
    let(:tracer) { described_class.new(flowchart) }

    it "replaces values under secret-bearing keys, recursively, and leaves others intact" do
      input = {
        password: "pw", "user_token" => "tok", apiKeyName: "irrelevant-shape",
        nested: { client_secret: "sec", ok: "fine" },
        list: [{ credentials: { inner: "x" } }, "plain"],
        name: "visible"
      }

      out = tracer.send(:redact_sensitive_keys, input)

      expect(out[:password]).to eq("[REDACTED]")
      expect(out["user_token"]).to eq("[REDACTED]")
      expect(out[:nested][:client_secret]).to eq("[REDACTED]")
      expect(out[:nested][:ok]).to eq("fine")
      expect(out[:list][0][:credentials]).to eq("[REDACTED]")
      expect(out[:list][1]).to eq("plain")
      expect(out[:name]).to eq("visible")
      # camelCase without the underscore does not match /api_key/ — documents the boundary
      expect(out[:apiKeyName]).to eq("irrelevant-shape")
    end
  end

  describe "#truncate_strings (snapshot value truncation helper)" do
    let(:tracer) { described_class.new(flowchart) }

    it "truncates strings longer than the limit with a marker, recursively" do
      long = "x" * 3_000
      input = { a: long, nested: { b: long }, list: [long, { c: long }], short: "ok", n: 42 }

      out = tracer.send(:truncate_strings, input)

      expect(out[:a].length).to be < 2_100
      expect(out[:a]).to end_with("…(truncated)")
      expect(out[:nested][:b]).to end_with("…(truncated)")
      expect(out[:list][0]).to end_with("…(truncated)")
      expect(out[:list][1][:c]).to end_with("…(truncated)")
      expect(out[:short]).to eq("ok")
      expect(out[:n]).to eq(42)
    end

    it "leaves strings at or under the limit untouched" do
      exact = "y" * 2_000

      expect(tracer.send(:truncate_strings, exact)).to eq(exact)
    end
  end

  describe "duplicate canvas labels" do
    let(:duplicate_label_flowchart) do
      config = {
        "elements" => [
          { "id" => "start_1", "type" => "start", "x" => 150, "y" => 100, "width" => 100, "height" => 45, "label" => "Begin", "properties" => { "inputs" => [], "outputs" => [] } },
          { "id" => "process_a", "type" => "process", "x" => 150, "y" => 200, "width" => 100, "height" => 45, "label" => "Process", "properties" => { "steps" => [], "inputs" => [], "outputs" => [] } },
          { "id" => "process_b", "type" => "process", "x" => 150, "y" => 300, "width" => 100, "height" => 45, "label" => "Process", "properties" => { "steps" => [], "inputs" => [], "outputs" => [] } },
          { "id" => "end_1", "type" => "end", "x" => 150, "y" => 400, "width" => 100, "height" => 45, "label" => "End", "properties" => {} }
        ],
        "connections" => [
          { "id" => "c1", "from" => "start_1", "to" => "process_a" },
          { "id" => "c2", "from" => "process_a", "to" => "process_b" },
          { "id" => "c3", "from" => "process_b", "to" => "end_1" }
        ],
        "metadata" => { "canvas" => { "width" => 1200, "height" => 800 }, "created_at" => Time.current.iso8601 }
      }
      create(:flowchart, configuration: config.to_json)
    end

    it "tags each same-labelled process with its own canvas element id from CANVAS" do
      result = described_class.new(duplicate_label_flowchart).call({})

      tagged = result.trace_nodes.select { |n| n[:element_id].present? && n[:id] != "Start.default" && !n[:id].to_s.start_with?("End.") }
      expect(tagged.map { |n| n[:element_id] }).to include("process_a", "process_b")
      expect(tagged.map { |n| n[:element_id] }.uniq.length).to eq(tagged.map { |n| n[:element_id] }.length)
    end
  end

  describe "End-with-response as a canvas step" do
    # Ends that write a response are Railway steps (CANVAS[:steps]); stepless
    # Ends live only in CANVAS[:ends]. The reached End is represented once as
    # End.success with that element's id and label — the End-with-response
    # step is omitted so the same element is not listed twice.

    let(:linear_end_with_response) do
      config = {
        "elements" => [
          { "id" => "s1", "type" => "start", "x" => 100, "y" => 50, "width" => 100, "height" => 45, "label" => "Start", "properties" => { "inputs" => [], "outputs" => [] } },
          {
            "id" => "p1", "type" => "process", "x" => 100, "y" => 150, "width" => 100, "height" => 45, "label" => "Mark Done",
            "properties" => {
              "steps" => [{
                "action" => "assign_value",
                "config" => { "resultVar" => "done", "valueType" => "string", "stringValue" => "yes" }
              }],
              "inputs" => [],
              "outputs" => []
            }
          },
          {
            "id" => "e1", "type" => "end", "x" => 100, "y" => 250, "width" => 100, "height" => 45, "label" => "Return Result",
            "properties" => { "responseType" => "value", "returnValue" => "ctx.done" }
          }
        ],
        "connections" => [
          { "id" => "c1", "from" => "s1", "to" => "p1" },
          { "id" => "c2", "from" => "p1", "to" => "e1" }
        ],
        "metadata" => { "canvas" => { "width" => 1200, "height" => 800 }, "created_at" => Time.current.iso8601 }
      }
      create(:flowchart, configuration: config.to_json)
    end

    let(:decision_to_end_with_response) do
      config = {
        "elements" => [
          { "id" => "s1", "type" => "start", "x" => 100, "y" => 50, "width" => 100, "height" => 45, "label" => "Start", "properties" => { "inputs" => [], "outputs" => [] } },
          {
            "id" => "d1", "type" => "decision", "x" => 100, "y" => 150, "width" => 100, "height" => 45, "label" => "Is vip",
            "properties" => {
              "routeBy" => "condition",
              "condition" => {
                "type" => "group",
                "joins" => [],
                "conditions" => [
                  { "kind" => "field", "leftOperand" => "ctx.params.vip", "operator" => "is_true", "rightOperand" => "" }
                ]
              }
            }
          },
          {
            "id" => "e_fast", "type" => "end", "x" => 220, "y" => 250, "width" => 100, "height" => 45, "label" => "Fast Exit",
            "properties" => { "responseType" => "value", "returnValue" => "ctx.params.marker" }
          },
          {
            "id" => "p_std", "type" => "process", "x" => 20, "y" => 250, "width" => 100, "height" => 45, "label" => "Standard Path",
            "properties" => {
              "steps" => [{
                "action" => "assign_value",
                "config" => { "resultVar" => "standard", "valueType" => "string", "stringValue" => "taken" }
              }],
              "inputs" => [],
              "outputs" => []
            }
          },
          { "id" => "e_std", "type" => "end", "x" => 20, "y" => 350, "width" => 100, "height" => 45, "label" => "Standard End", "properties" => {} }
        ],
        "connections" => [
          { "id" => "c1", "from" => "s1", "to" => "d1" },
          { "id" => "c2", "from" => "d1", "to" => "e_fast", "label" => "Yes", "matchValue" => "true" },
          { "id" => "c3", "from" => "d1", "to" => "p_std", "label" => "No", "matchValue" => "false" },
          { "id" => "c4", "from" => "p_std", "to" => "e_std" }
        ],
        "metadata" => { "canvas" => { "width" => 1200, "height" => 800 }, "created_at" => Time.current.iso8601 }
      }
      create(:flowchart, configuration: config.to_json)
    end

    let(:decision_to_stepless_end) do
      config = {
        "elements" => [
          { "id" => "s1", "type" => "start", "x" => 100, "y" => 50, "width" => 100, "height" => 45, "label" => "Start", "properties" => { "inputs" => [], "outputs" => [] } },
          {
            "id" => "d1", "type" => "decision", "x" => 100, "y" => 150, "width" => 100, "height" => 45, "label" => "Is vip",
            "properties" => {
              "routeBy" => "condition",
              "condition" => {
                "type" => "group",
                "joins" => [],
                "conditions" => [
                  { "kind" => "field", "leftOperand" => "ctx.params.vip", "operator" => "is_true", "rightOperand" => "" }
                ]
              }
            }
          },
          { "id" => "e_yes", "type" => "end", "x" => 220, "y" => 250, "width" => 100, "height" => 45, "label" => "Yes End", "properties" => {} },
          {
            "id" => "p_no", "type" => "process", "x" => 20, "y" => 250, "width" => 100, "height" => 45, "label" => "Other Path",
            "properties" => {
              "steps" => [{
                "action" => "assign_value",
                "config" => { "resultVar" => "other", "valueType" => "string", "stringValue" => "taken" }
              }],
              "inputs" => [],
              "outputs" => []
            }
          },
          { "id" => "e_no", "type" => "end", "x" => 20, "y" => 350, "width" => 100, "height" => 45, "label" => "No End", "properties" => {} }
        ],
        "connections" => [
          { "id" => "c1", "from" => "s1", "to" => "d1" },
          { "id" => "c2", "from" => "d1", "to" => "e_yes", "label" => "Yes", "matchValue" => "true" },
          { "id" => "c3", "from" => "d1", "to" => "p_no", "label" => "No", "matchValue" => "false" },
          { "id" => "c4", "from" => "p_no", "to" => "e_no" }
        ],
        "metadata" => { "canvas" => { "width" => 1200, "height" => 800 }, "created_at" => Time.current.iso8601 }
      }
      create(:flowchart, configuration: config.to_json)
    end

    it "maps End.success to the End-with-response element on a linear flow" do
      result = described_class.new(linear_end_with_response).call({})

      expect(result.error).to be_nil
      expect(result.success?).to be true
      expect(result.ctx[:response]).to eq("yes")

      finish = result.trace_nodes.find { |n| n[:id] == "End.success" }
      expect(finish).to be_present
      expect(finish[:element_id]).to eq("e1")
      expect(finish[:label]).to eq("Return Result")
      expect(finish[:status]).to eq("success")
      expect(result.trace_nodes.count { |n| n[:element_id] == "e1" }).to eq(1)
    end

    def with_end_body(flowchart, replacement)
      original = "ctx[:response] = ctx[:done]\n    true\n"
      expect(flowchart.activity).to include(original)
      flowchart.update_column(:activity, flowchart.activity.sub(original, "ctx[:response] = ctx[:done]\n    #{replacement}\n"))
      flowchart
    end

    it "keeps a failing End-with-response step visible with its element" do
      result = described_class.new(with_end_body(linear_end_with_response, "false")).call({})

      expect(result.success?).to be false
      failed = result.trace_nodes.find { |n| n[:element_id] == "e1" }
      expect(failed).to include(id: "return_result", label: "Return Result", status: "failure")
      expect(result.trace_nodes.last[:id]).to eq("End.failure")
    end

    it "keeps a raising End-with-response step visible with its element" do
      result = described_class.new(with_end_body(linear_end_with_response, 'raise "boom"')).call({})

      expect(result.success?).to be false
      failed = result.trace_nodes.find { |n| n[:element_id] == "e1" }
      expect(failed).to include(id: "return_result", label: "Return Result", status: "failure")
    end

    it "maps End.success to the End-with-response element on a decision branch" do
      result = described_class.new(decision_to_end_with_response).call(params: { "vip" => true, "marker" => "fast" })

      expect(result.error).to be_nil
      expect(result.success?).to be true
      expect(result.ctx[:response]).to eq("fast")

      ids = result.trace_nodes.map { |n| n[:id] }
      expect(ids).to include("Start.default", "is_vip")
      expect(ids).not_to include("standard_path", "collect_errors")

      decision = result.trace_nodes.find { |n| n[:id] == "is_vip" }
      expect(decision[:branch]).to eq("Yes")

      finish = result.trace_nodes.find { |n| n[:id] == "End.success" }
      expect(finish).to be_present
      expect(finish[:element_id]).to eq("e_fast")
      expect(finish[:label]).to eq("Fast Exit")
      expect(finish[:status]).to eq("success")
      expect(result.trace_nodes.count { |n| n[:element_id] == "e_fast" }).to eq(1)
    end

    it "maps End.success to a stepless End reached straight from a decision" do
      result = described_class.new(decision_to_stepless_end).call(params: { "vip" => true })

      expect(result.error).to be_nil
      expect(result.success?).to be true

      ids = result.trace_nodes.map { |n| n[:id] }
      expect(ids).to include("Start.default", "is_vip")
      expect(ids).not_to include("other_path", "collect_errors")

      decision = result.trace_nodes.find { |n| n[:id] == "is_vip" }
      expect(decision[:branch]).to eq("Yes")

      finish = result.trace_nodes.find { |n| n[:id] == "End.success" }
      expect(finish).to be_present
      expect(finish[:element_id]).to eq("e_yes")
      expect(finish[:label]).to eq("Yes End")
      expect(finish[:status]).to eq("success")
    end
  end

  describe "two references to one subflow" do
    let(:child) do
      create(:flowchart, :launched_status, customer: entity.customer, configuration: {
        "elements" => [
          { "id" => "start", "type" => "start", "label" => "Child Start", "properties" => {} },
          { "id" => "assign", "type" => "process", "label" => "Assign", "properties" => { "steps" => [
            { "action" => "assign_value", "config" => { "resultVar" => "child_marker", "valueType" => "string", "stringValue" => "ran" }
            }
          ] } },
          { "id" => "end", "type" => "end", "label" => "Child End", "properties" => {} }
        ],
        "connections" => [
          { "id" => "cc1", "from" => "start", "to" => "assign" },
          { "id" => "cc2", "from" => "assign", "to" => "end" }
        ],
        "metadata" => {}
      }.to_json)
    end

    let(:parent) do
      child
      create(:flowchart, customer: entity.customer, configuration: {
        "elements" => [
          { "id" => "s1", "type" => "start", "x" => 100, "y" => 50, "width" => 100, "height" => 45, "label" => "Start", "properties" => {} },
          {
            "id" => "sf1", "type" => "subflow", "x" => 100, "y" => 150, "width" => 100, "height" => 45, "label" => "First Check",
            "properties" => { "flowchartId" => child.id, "inputs" => [{ "value" => "ctx" }], "outputs" => [{ "value" => "signal" }, { "value" => "ctx" }] }
          },
          {
            "id" => "sf2", "type" => "subflow", "x" => 100, "y" => 250, "width" => 100, "height" => 45, "label" => "Second Check",
            "properties" => { "flowchartId" => child.id, "inputs" => [{ "value" => "ctx" }], "outputs" => [{ "value" => "signal" }, { "value" => "ctx" }] }
          },
          { "id" => "e1", "type" => "end", "x" => 100, "y" => 350, "width" => 100, "height" => 45, "label" => "End", "properties" => {} }
        ],
        "connections" => [
          { "id" => "c1", "from" => "s1", "to" => "sf1" },
          { "id" => "c2", "from" => "sf1", "to" => "sf2" },
          { "id" => "c3", "from" => "sf2", "to" => "e1" }
        ],
        "metadata" => { "canvas" => { "width" => 1200, "height" => 800 }, "created_at" => Time.current.iso8601 }
      }.to_json)
    end

    it "traces both subflow steps and hides the child's own terminals" do
      result = Current.set(customer: entity.customer, user: find_or_create_platform_owner) {
        described_class.new(parent).call({})
      }

      expect(result.error).to be_nil
      expect(result.success?).to be true

      ids = result.trace_nodes.map { |n| n[:id] }
      expect(ids).to include("Start.default", "first_check", "second_check")
      expect(ids.count { |id| id == "Start.default" }).to eq(1)
      expect(ids.count { |id| id.to_s.start_with?("End.") }).to eq(1)
      expect(ids).not_to include("collect_errors", "assign")

      first = result.trace_nodes.find { |n| n[:id] == "first_check" }
      second = result.trace_nodes.find { |n| n[:id] == "second_check" }
      expect(first[:element_id]).to eq("sf1")
      expect(first[:label]).to eq("First Check")
      expect(second[:element_id]).to eq("sf2")
      expect(second[:label]).to eq("Second Check")

      finish = result.trace_nodes.find { |n| n[:id].to_s.start_with?("End.") }
      expect(finish[:element_id]).to eq("e1")
    end
  end

  describe "owner test-run error translation" do
    def raising_flowchart(message)
      config = {
        "elements" => [
          { "id" => "start_1", "type" => "start", "x" => 150, "y" => 100, "width" => 100, "height" => 45, "label" => "Begin", "properties" => { "inputs" => [], "outputs" => [] } },
          { "id" => "boom_1", "type" => "process", "x" => 150, "y" => 200, "width" => 100, "height" => 45, "label" => "Boom Step", "properties" => { "steps" => [], "inputs" => [], "outputs" => [] } },
          { "id" => "end_1", "type" => "end", "x" => 150, "y" => 300, "width" => 100, "height" => 45, "label" => "End", "properties" => {} }
        ],
        "connections" => [
          { "id" => "conn_1", "from" => "start_1", "to" => "boom_1" },
          { "id" => "conn_2", "from" => "boom_1", "to" => "end_1" }
        ],
        "metadata" => { "canvas" => { "width" => 1200, "height" => 800 }, "created_at" => Time.current.iso8601 }
      }
      f = create(:flowchart, configuration: config.to_json)
      f.update_column(:activity, f.activity.sub(
        /def boom_step\(ctx, \*\*\)\n    true/,
        "def boom_step(ctx, **)\n    raise #{message.inspect}"
      ))
      f
    end

    it "keeps SECRET_EXCEPTION_TEXT out of Result#error and uses the translated generic message" do
      result = described_class.new(raising_flowchart("SECRET_EXCEPTION_TEXT")).call({})

      expect(result.success?).to be false
      expect(result.error).to eq(I18n.t("flowchart_elements.trace.errors.execution_failed"))
      expect(result.error).not_to include("SECRET_EXCEPTION_TEXT")
      expect(result.error).not_to include("Execution error:")
    end

    it "yields the zh-CN execution_failed message and still omits the exception text" do
      result = I18n.with_locale(:"zh-CN") {
        described_class.new(raising_flowchart("SECRET_EXCEPTION_TEXT")).call({})
      }

      expect(result.error).to eq(I18n.t("flowchart_elements.trace.errors.execution_failed", locale: :"zh-CN"))
      expect(result.error).not_to include("SECRET_EXCEPTION_TEXT")
      expect(result.error).not_to eq("Execution failed")
    end
  end

  describe "generated class without CANVAS" do
    it "refuses to run and asks for regeneration instead of an unmapped success" do
      f = create(:flowchart, :simple)
      f.update_column(:activity, <<~RUBY)
        class NoCanvasActivity < Trailblazer::Activity::Railway
          step :ok
          def ok(ctx, **)
            ctx[:ran_without_canvas] = true
            true
          end
        end
      RUBY

      result = described_class.new(f).call({})

      expect(result.success?).to be false
      expect(result.error).to eq(I18n.t("flowchart_elements.trace.errors.must_regenerate"))
      expect(result.ctx[:ran_without_canvas]).to be_nil
      expect(result.trace_nodes).to eq([])
    end

    it "runs untraced without CANVAS because only trace mapping needs it" do
      f = create(:flowchart, :simple)
      f.update_column(:activity, <<~RUBY)
        class NoCanvasUntracedActivity < Trailblazer::Activity::Railway
          step :ok
          def ok(ctx, **)
            ctx[:ran_without_canvas] = true
            true
          end
        end
      RUBY

      result = described_class.new(f).call({}, trace: false)

      expect(result.success?).to be true
      expect(result.ctx[:ran_without_canvas]).to be true
    end
  end

  describe "trace-node cap" do
    def loop_flowchart(item_count)
      elements = [
        { "id" => "start", "label" => "Start", "type" => "start", "properties" => {} },
        {
          "id" => "repeat", "label" => "Repeat", "type" => "loop",
          "properties" => { "loopType" => "for_each", "collection" => "items", "itemVariable" => "item", "maxIterations" => item_count }
        },
        { "id" => "work", "label" => "Work", "type" => "process", "properties" => { "steps" => [] } },
        { "id" => "after", "label" => "After", "type" => "process", "properties" => { "steps" => [] } },
        { "id" => "end", "label" => "End", "type" => "end", "properties" => { "responseType" => "none" } }
      ]
      edges = [["start", "repeat"], ["repeat", "after"], ["repeat", "work"], ["work", "repeat"], ["after", "end"]]
      config = {
        "elements" => elements,
        "connections" => edges.each_with_index.map { |edge, i|
          { "id" => i.to_s, "from" => edge[0], "to" => edge[1] }
        },
        "metadata" => { "canvas" => { "width" => 1200, "height" => 800 } }
      }
      record = create(:flowchart, name: "Trace Cap #{item_count}", configuration: config.to_json)
      code = ActivityGenerator.new(record).generate
      expect(code).to be_present
      record.update_column(:activity, code)
      record
    end

    it "keeps the first 500 nodes of a 2,000-item for_each and marks the Result truncated" do
      items = (1..2_000).to_a
      result = described_class.new(loop_flowchart(2_000)).call(items: items)

      expect(result.error).to be_nil
      expect(result.trace_nodes.size).to be <= ActivityTracer::MAX_TRACE_NODES
      expect(result.trace_nodes.size).to eq(ActivityTracer::MAX_TRACE_NODES)
      expect(result.truncated).to be true
    end

    it "leaves truncated false on a small for_each" do
      result = described_class.new(loop_flowchart(3)).call(items: [10, 20, 30])

      expect(result.error).to be_nil
      expect(result.success?).to be true
      expect(result.trace_nodes.size).to be < ActivityTracer::MAX_TRACE_NODES
      expect(result.truncated).to be false
    end
  end

  describe "failing child Subprocess" do
    let(:validated_entity) do
      create(:entity, customer: entity.customer, property_schema: [
        { "name" => "Name", "name_slug" => "name", "type" => "String", "validators" => [{ "type" => "presence" }] }
      ].to_json)
    end

    let(:child) do
      fc = Flowchart.new_with_defaults(
        name: "Create Validated Child",
        customer: validated_entity.customer,
        template: "page_record"
      )
      fc.status = :launched
      fc.save!
      fc
    end

    let(:parent) do
      child
      create(:flowchart, customer: entity.customer, configuration: {
        "elements" => [
          { "id" => "s1", "type" => "start", "x" => 100, "y" => 50, "width" => 100, "height" => 45, "label" => "Start", "properties" => {} },
          {
            "id" => "sf1", "type" => "subflow", "x" => 100, "y" => 150, "width" => 100, "height" => 45, "label" => "Child Create",
            "properties" => { "flowchartId" => child.id, "inputs" => [{ "value" => "ctx" }], "outputs" => [{ "value" => "signal" }, { "value" => "ctx" }] }
          },
          { "id" => "e1", "type" => "end", "x" => 100, "y" => 250, "width" => 100, "height" => 45, "label" => "End", "properties" => {} }
        ],
        "connections" => [
          { "id" => "c1", "from" => "s1", "to" => "sf1" },
          { "id" => "c2", "from" => "sf1", "to" => "e1" }
        ],
        "metadata" => { "canvas" => { "width" => 1200, "height" => 800 }, "created_at" => Time.current.iso8601 }
      }.to_json)
    end

    it "fails the parent and puts the child's collect_errors messages first in ctx[:errors]" do
      record = EntityEntry.build_for(validated_entity).new(
        entity: validated_entity, customer_id: validated_entity.customer_id
      )
      result = Current.set(customer: entity.customer, user: find_or_create_platform_owner) {
        described_class.new(parent).call(
          params: {},
          customer_id: validated_entity.customer_id,
          bound_entity: validated_entity,
          audience: :admin,
          model: record,
          page_record: record
        )
      }

      expect(result.success?).to be false
      expect(result.error).to be_nil
      expect(result.ctx[:errors]).to be_present
      expect(result.ctx[:errors].first).to match(/can't be blank/i)
    end
  end

  describe "RunContext deadline" do
    let(:budget_activity) do
      <<~RUBY
        class ActivityTracerRunContextActivity < Trailblazer::Activity::Railway
          CANVAS = { steps: { process: "process_1" } }.freeze
          step :process
          def process(ctx, **)
            ctx[:remaining] = FlowchartRuntime::RunContext.remaining
            ctx[:deadline_set] = !FlowchartRuntime::RunContext.deadline.nil?
            true
          end
        end
      RUBY
    end

    def flowchart_with_budget
      create(:flowchart, :simple).tap do |record|
        record.update_column(:activity, budget_activity)
      end
    end

    it "sets a deadline around a traced run and clears it afterwards" do
      result = described_class.new(flowchart_with_budget).call({})

      expect(result.success?).to be true
      expect(result.ctx[:deadline_set]).to be true
      expect(result.ctx[:remaining]).to be <= ActivityTracer::EXECUTION_TIMEOUT_SECONDS
      expect(FlowchartRuntime::RunContext.deadline).to be_nil
    end

    it "sets a deadline around an untraced run and clears it afterwards" do
      result = described_class.new(flowchart_with_budget).call({}, trace: false)

      expect(result.success?).to be true
      expect(result.ctx[:deadline_set]).to be true
      expect(result.ctx[:remaining]).to be <= ActivityTracer::EXECUTION_TIMEOUT_SECONDS
      expect(FlowchartRuntime::RunContext.deadline).to be_nil
    end
  end
end

