# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartServerValidator do
  let(:customer)  { create(:customer) }
  let(:entity)    { create(:entity, customer: customer) }
  let(:flowchart) { create(:flowchart, customer: customer) }

  # --- configuration builders (mirror spec/factories/flowcharts.rb shapes) ---

  def element(id, type, label, properties = {})
    {
      "id" => id, "type" => type, "x" => 100, "y" => 100,
      "width" => 100, "height" => 45, "label" => label,
      "properties" => properties
    }
  end

  def linear_config(middle_element)
    {
      "elements" => [
        element("start_1", "start", "Start"),
        middle_element,
        element("end_1", "end", "End")
      ],
      "connections" => [
        { "id" => "c1", "from" => "start_1", "to" => middle_element["id"] },
        { "id" => "c2", "from" => middle_element["id"], "to" => "end_1" }
      ],
      "metadata" => {}
    }
  end

  def subflow_config(target_flowchart_id)
    linear_config(
      element("subflow_1", "subflow", "Call Subflow", { "flowchartId" => target_flowchart_id })
    )
  end

  def problems_for(configuration, record: flowchart)
    described_class.new(record, configuration).call
  end

  describe "#call" do
    context "with an empty elements array" do
      it "returns [] without invoking ActivityGenerator" do
        flowchart # create up front — the model's save callback uses ActivityGenerator
        expect(ActivityGenerator).not_to receive(:new)

        expect(problems_for({ "elements" => [], "connections" => [] })).to eq([])
      end
    end

    it "never persists the submitted configuration" do
      expect {
        problems_for(subflow_config(999_999_999))
      }.not_to change { flowchart.reload.configuration }
    end

    it "validates the SUBMITTED configuration, not the persisted one" do
      # Persisted factory config is clean; the submitted one has a broken subflow.
      problems = problems_for(subflow_config(999_999_999))

      expect(problems.map { |p| p[:type] }).to include("subflow_inaccessible")
    end

    context "with a clean configuration" do
      it "returns no problems" do
        config = linear_config(element("process_1", "process", "Do Work", { "steps" => [] }))

        expect(problems_for(config)).to eq([])
      end
    end

    describe "payload cap" do
      it "returns a single server_check_unavailable warning when elements exceed the cap" do
        flowchart # create up front — the model's save callback uses ActivityGenerator
        expect(ActivityGenerator).not_to receive(:new)

        config = {
          "elements" => Array.new(1_001) { |i| element("e#{i}", "process", "P#{i}", { "steps" => [] }) },
          "connections" => [],
          "metadata" => {}
        }

        expect(problems_for(config)).to eq([{
          type: "server_check_unavailable",
          severity: "warning",
          element_id: nil,
          connection_id: nil,
          message: "Flowchart too large for server-side checks",
          fix_hint: nil
        }])
      end

      it "returns a single server_check_unavailable warning when connections exceed the cap" do
        flowchart # create up front — the model's save callback uses ActivityGenerator
        expect(ActivityGenerator).not_to receive(:new)

        config = linear_config(element("process_1", "process", "Do Work", { "steps" => [] }))
        config["connections"] = Array.new(5_001) { |i| { "id" => "c#{i}", "from" => "start_1", "to" => "end_1" } }

        problems = problems_for(config)

        expect(problems.size).to eq(1)
        expect(problems.first[:type]).to eq("server_check_unavailable")
        expect(problems.first[:severity]).to eq("warning")
      end
    end

    describe "problem schema" do
      it "emits hashes with exactly the keys type, severity, element_id, connection_id, message, fix_hint" do
        problems = problems_for(subflow_config(999_999_999))

        expect(problems).not_to be_empty
        problems.each do |problem|
          expect(problem.keys).to match_array(%i[type severity element_id connection_id message fix_hint])
          expect(%w[error warning]).to include(problem[:severity])
        end
      end
    end
  end

  describe "subflow accessibility" do
    context "when a subflow references a nonexistent flowchart id" do
      it "returns one subflow_inaccessible error on that element" do
        problems = problems_for(subflow_config(999_999_999))
        inaccessible = problems.select { |p| p[:type] == "subflow_inaccessible" }

        expect(inaccessible.size).to eq(1)
        expect(inaccessible.first[:severity]).to eq("error")
        expect(inaccessible.first[:element_id]).to eq("subflow_1")
        expect(inaccessible.first[:fix_hint]).to be_present
      end
    end

    context "when a subflow references another customer's customer_specific flowchart" do
      let(:other_customer) { create(:customer) }
      let(:other_entity)   { create(:entity, customer: other_customer) }
      let!(:foreign) { create(:flowchart, customer: other_customer) }

      it "returns subflow_inaccessible" do
        problems = problems_for(subflow_config(foreign.id))

        expect(problems.map { |p| p[:type] }).to include("subflow_inaccessible")
      end

      it "does not reveal whether the flowchart exists in another tenant" do
        cross_tenant_message = problems_for(subflow_config(foreign.id))
                               .find { |p| p[:type] == "subflow_inaccessible" }[:message]
        missing_message = problems_for(subflow_config(999_999_999))
                          .find { |p| p[:type] == "subflow_inaccessible" }[:message]

        expect(cross_tenant_message).to eq(missing_message)
        expect(cross_tenant_message).not_to include(foreign.name)
      end
    end

    context "when a subflow references a shared flowchart" do
      let!(:shared) { create(:flowchart, :shared_type) }

      it "reports no subflow problems" do
        problems = problems_for(subflow_config(shared.id))

        expect(problems.map { |p| p[:type] })
          .not_to include("subflow_inaccessible", "subflow_cycle")
      end
    end

    # A shared flowchart has customer_id NULL, so per the accessibility rule
    # (shared OR same customer as the parent) it may ONLY reference other
    # shared flowcharts — any customer_specific target is out of reach.
    context "when the parent flowchart is shared (customer_id nil)" do
      let(:shared_parent) { create(:flowchart, :shared_type) }

      it "flags a customer_specific subflow as inaccessible" do
        tenant_owned = create(:flowchart, customer: customer)

        problems = problems_for(subflow_config(tenant_owned.id), record: shared_parent)

        expect(problems.map { |p| p[:type] }).to include("subflow_inaccessible")
      end

      it "accepts another shared flowchart as a subflow" do
        other_shared = create(:flowchart, :shared_type)

        problems = problems_for(subflow_config(other_shared.id), record: shared_parent)

        expect(problems.map { |p| p[:type] })
          .not_to include("subflow_inaccessible", "subflow_cycle")
      end
    end
  end

  describe "subflow cycles" do
    context "when a subflow references its own flowchart (self-reference)" do
      it "returns subflow_cycle on the subflow element" do
        problems = problems_for(subflow_config(flowchart.id))
        cycle = problems.find { |p| p[:type] == "subflow_cycle" }

        expect(cycle).to be_present
        expect(cycle[:severity]).to eq("error")
        expect(cycle[:element_id]).to eq("subflow_1")
      end
    end

    context "with a transitive cycle (A -> B, B's persisted config -> A)" do
      let!(:flowchart_b) do
        create(:flowchart, customer: customer, configuration: subflow_config(flowchart.id).to_json)
      end

      it "detects the cycle and terminates" do
        problems = problems_for(subflow_config(flowchart_b.id))
        cycle = problems.find { |p| p[:type] == "subflow_cycle" }

        expect(cycle).to be_present
        expect(cycle[:element_id]).to eq("subflow_1")
      end
    end

    context "with a 3-level cycle (A -> B, B -> C, C -> A)" do
      # Creation order matters: C must exist before B can reference it, and
      # A (the subject `flowchart`) before C. The cycle only closes through
      # A's SUBMITTED configuration, so every persisted record stays valid.
      let!(:flowchart_c) do
        create(:flowchart, customer: customer, configuration: subflow_config(flowchart.id).to_json)
      end
      let!(:flowchart_b) do
        create(:flowchart, customer: customer, configuration: subflow_config(flowchart_c.id).to_json)
      end

      it "detects the cycle across the full chain" do
        problems = problems_for(subflow_config(flowchart_b.id))
        cycle = problems.find { |p| p[:type] == "subflow_cycle" }

        expect(cycle).to be_present
        expect(cycle[:element_id]).to eq("subflow_1")
      end
    end

    context "with a deep chain that does NOT cycle (A -> B -> C, C clean)" do
      let!(:flowchart_c) { create(:flowchart, customer: customer) }
      let!(:flowchart_b) do
        create(:flowchart, customer: customer, configuration: subflow_config(flowchart_c.id).to_json)
      end

      it "reports no subflow problems (no false-positive cycle)" do
        problems = problems_for(subflow_config(flowchart_b.id))

        expect(problems.map { |p| p[:type] })
          .not_to include("subflow_cycle", "subflow_inaccessible")
      end
    end
  end

  describe "codegen dry-run" do
    context "with an unknown step action" do
      it "returns a structured codegen failure mapped to the process element" do
        config = linear_config(
          element("process_1", "process", "Do Work",
                  { "steps" => [{ "id" => "s1", "action" => "no_such_action", "config" => {} }] })
        )
        problems = problems_for(config)
        failure = problems.find { |p| p[:type] == "codegen_failed" }

        expect(failure).to be_present
        expect(failure[:severity]).to eq("error")
        expect(failure[:element_id]).to eq("process_1")
        expect(failure[:message]).to include("unknown_step_action")
      end
    end

    context "with two unknown step actions in a chain of single-action processes" do
      it "fails generation without emitting success-shaped TODO methods" do
        config = {
          "elements" => [
            element("start_1", "start", "Start"),
            element("process_1", "process", "Do Work",
                    { "steps" => [{ "id" => "s1", "action" => "first_bogus_action", "config" => {} }] }),
            element("process_2", "process", "Do More",
                    { "steps" => [{ "id" => "s2", "action" => "second_bogus_action", "config" => {} }] }),
            element("end_1", "end", "End")
          ],
          "connections" => [
            { "id" => "c1", "from" => "start_1", "to" => "process_1" },
            { "id" => "c2", "from" => "process_1", "to" => "process_2" },
            { "id" => "c3", "from" => "process_2", "to" => "end_1" }
          ],
          "metadata" => {}
        }
        failures = problems_for(config).select { |p| p[:type] == "codegen_failed" }

        expect(failures).not_to be_empty
        expect(failures.map { |failure| failure[:message] }.join).to include("unknown_step_action")
        expect(failures.map { |failure| failure[:element_id] }).to include("process_1").or include("process_2")
      end
    end

    context "with an invalid structure (element not reachable from start)" do
      it "returns codegen_failed errors carrying the generator's structure messages" do
        config = {
          "elements" => [
            element("start_1", "start", "Start"),
            element("end_1", "end", "End"),
            element("orphan_1", "process", "Orphan", { "steps" => [] })
          ],
          "connections" => [{ "id" => "c1", "from" => "start_1", "to" => "end_1" }],
          "metadata" => {}
        }
        problems = problems_for(config)
        failed = problems.select { |p| p[:type] == "codegen_failed" }

        expect(failed).not_to be_empty
        expect(failed).to all(include(severity: "error", element_id: nil))
        expect(failed.map { |p| p[:message] }.join).to include("Orphan")
        expect(problems.map { |p| p[:type] }).not_to include("codegen_todo")
      end
    end

    context "when elements are present but the connections key is missing entirely" do
      it "returns codegen_failed structure errors instead of raising" do
        config = {
          "elements" => [
            element("start_1", "start", "Start"),
            element("process_1", "process", "Do Work", { "steps" => [] }),
            element("end_1", "end", "End")
          ],
          "metadata" => {}
        }

        problems = nil
        expect { problems = problems_for(config) }.not_to raise_error

        failed = problems.select { |p| p[:type] == "codegen_failed" }
        expect(failed).not_to be_empty
        expect(failed.map { |p| p[:message] }.join).to include("no incoming connections")
      end
    end

    context "when the generator returns nil despite a valid structure" do
      it "returns a codegen_failed error" do
        flowchart # create up front — the model's save callback uses ActivityGenerator
        generator = instance_double(ActivityGenerator, structure_errors: [], generate: nil)
        allow(ActivityGenerator).to receive(:new).and_return(generator)

        config = linear_config(element("process_1", "process", "Do Work", { "steps" => [] }))
        problems = problems_for(config)

        expect(problems.map { |p| p[:type] }).to include("codegen_failed")
      end
    end

    context "when the generator raises" do
      it "returns codegen_failed naming the exception class only (no message content)" do
        flowchart # create up front — the model's save callback uses ActivityGenerator
        generator = instance_double(ActivityGenerator, structure_errors: [])
        allow(generator).to receive(:generate).and_raise(RuntimeError, "secret user content")
        allow(ActivityGenerator).to receive(:new).and_return(generator)

        config = linear_config(element("process_1", "process", "Do Work", { "steps" => [] }))
        failed = problems_for(config).find { |p| p[:type] == "codegen_failed" }

        expect(failed).to be_present
        expect(failed[:message]).to include("RuntimeError")
        expect(failed[:message]).not_to include("secret user content")
      end
    end

    context "when the dry-run exceeds the timeout" do
      it "returns the single codegen_check_timeout warning" do
        flowchart # create up front — the model's save callback uses ActivityGenerator
        generator = instance_double(ActivityGenerator, structure_errors: [])
        allow(generator).to receive(:generate).and_raise(Timeout::Error)
        allow(ActivityGenerator).to receive(:new).and_return(generator)

        config = linear_config(element("process_1", "process", "Do Work", { "steps" => [] }))
        problems = problems_for(config)

        expect(problems.size).to eq(1)
        expect(problems.first[:type]).to eq("codegen_check_timeout")
        expect(problems.first[:severity]).to eq("warning")
        expect(problems.first[:message]).to eq(
          "Server-side validation timed out after 10 seconds — problems may be incomplete"
        )
      end

      it "translates the timeout warning in zh-CN" do
        flowchart
        generator = instance_double(ActivityGenerator, structure_errors: [])
        allow(generator).to receive(:generate).and_raise(Timeout::Error)
        allow(ActivityGenerator).to receive(:new).and_return(generator)

        config = linear_config(element("process_1", "process", "Do Work", { "steps" => [] }))
        problems = I18n.with_locale(:"zh-CN") { problems_for(config) }

        expect(problems.first[:message]).to eq("服务器端校验在 10 秒后超时，问题列表可能不完整")
      end
    end

    context "when the payload is too large in zh-CN" do
      it "translates the server_check_unavailable warning" do
        flowchart
        config = {
          "elements" => Array.new(1_001) { |i| element("e#{i}", "process", "P#{i}", { "steps" => [] }) },
          "connections" => [],
          "metadata" => {}
        }

        problems = I18n.with_locale(:"zh-CN") { problems_for(config) }

        expect(problems.first[:message]).to eq("流程图过大，无法执行服务器端检查")
      end
    end

    context "when the subflow walk exceeds the timeout" do
      it "returns the single codegen_check_timeout warning" do
        flowchart # create up front — the stub below must not affect creation

        # The subflow phase resolves targets via Flowchart.find_by; raising
        # here simulates the overall deadline expiring mid-walk.
        allow(Flowchart).to receive(:find_by).and_raise(Timeout::Error)

        problems = problems_for(subflow_config(999_999_999))

        expect(problems.size).to eq(1)
        expect(problems.first[:type]).to eq("codegen_check_timeout")
        expect(problems.first[:severity]).to eq("warning")
      end
    end
  end

  describe "codegen dry-run gating" do
    before { flowchart } # create up front — the model's save callback uses ActivityGenerator

    it "skips the dry run when the subflow checks return an error" do
      expect(ActivityGenerator).not_to receive(:new)

      problems = problems_for(subflow_config(999_999_999))

      expect(problems.map { |p| p[:type] }).to eq(["subflow_inaccessible"])
    end

    it "skips the dry run when the config checks return an error" do
      expect(ActivityGenerator).not_to receive(:new)

      config = linear_config(
        element("process_1", "process", "Do Work",
                { "steps" => [{ "id" => "s1", "action" => "find_model", "config" => { "findBy" => "nonsense_strategy" } }] })
      )

      expect(problems_for(config).map { |p| p[:type] }.uniq).to eq(["step_config_invalid"])
    end

    it "runs the dry run when the subflow and config checks are clean" do
      generator = instance_double(ActivityGenerator, structure_errors: [], generate: nil)
      allow(ActivityGenerator).to receive(:new).and_return(generator)

      problems = problems_for(linear_config(element("process_1", "process", "Do Work", { "steps" => [] })))

      expect(problems.map { |p| p[:type] }).to eq(["codegen_failed"])
    end
  end

  describe "subflow element with blank flowchartId and subflowId" do
    # Covers the `next if target_id.blank?` guard in subflow_problems.
    it "produces no subflow problems when both ids are absent" do
      config = linear_config(
        element("subflow_1", "subflow", "Call Subflow", {})
      )
      problems = problems_for(config)

      expect(problems.map { |p| p[:type] })
        .not_to include("subflow_inaccessible", "subflow_cycle")
    end

    it "produces no subflow problems when flowchartId is blank string" do
      config = linear_config(
        element("subflow_1", "subflow", "Call Subflow", { "flowchartId" => "" })
      )
      problems = problems_for(config)

      expect(problems.map { |p| p[:type] })
        .not_to include("subflow_inaccessible", "subflow_cycle")
    end
  end

  describe "config_validation_problems" do
    # Helper: build a process element with a single step
    def process_with_step(step_id, action, config_hash, label: nil)
      step = { "id" => step_id, "action" => action, "config" => config_hash }
      step["label"] = label if label
      element("process_1", "process", "Do Work", { "steps" => [step] })
    end

    context "case 1 — process step with invalid config" do
      it "returns a step_config_invalid problem with the right element_id and generator error text" do
        # find_model with an unknown findBy → generator reports the error
        bad_step_element = process_with_step(
          "s1", "find_model",
          { "findBy" => "nonsense_strategy" },
          label: "Look Up User"
        )
        config = linear_config(bad_step_element)

        problems = problems_for(config)
        config_problems = problems.select { |p| p[:type] == "step_config_invalid" }

        expect(config_problems).not_to be_empty
        expect(config_problems.first[:severity]).to eq("error")
        expect(config_problems.first[:element_id]).to eq("process_1")
        # message must contain generator's error text about the invalid findBy
        expect(config_problems.first[:message]).to include("findBy")
        expect(config_problems.first[:fix_hint]).to eq("Fix this step's configuration")
      end
    end

    context "case 2 — non-process element with invalid config" do
      context "removed Join element" do
        it "returns an explicit structural generation failure" do
          join_el = element("join_1", "join", "Merge Paths",
                            { "joinStrategy" => "wait_n" })
          config = linear_config(join_el)

          problems = problems_for(config)
          failures = problems.select { |p| p[:type] == "codegen_failed" }

          expect(failures).not_to be_empty
          expect(failures.first[:severity]).to eq("error")
          expect(failures.first[:message]).to include("unsupported structural type 'join'")
        end
      end

      context "removed Switch element" do
        it "returns an explicit structural generation failure" do
          switch_el = element("switch_1", "switch", "Route By Status",
                              { "sourceVariable" => "" })
          config = linear_config(switch_el)

          problems = problems_for(config)
          failures = problems.select { |p| p[:type] == "codegen_failed" }

          expect(failures).not_to be_empty
          expect(failures.first[:severity]).to eq("error")
          expect(failures.first[:message]).to include("unsupported structural type 'switch'")
        end
      end
    end

    context "case 3 — valid flowchart produces no config_invalid problems" do
      it "returns no step_config_invalid or element_config_invalid problems" do
        # find_model with a valid strategy that does not require a field
        valid_step_element = process_with_step(
          "s1", "find_model",
          { "findStrategy" => "find", "resultVar" => "record" }
        )
        config = linear_config(valid_step_element)

        problems = problems_for(config)
        config_problem_types = problems.map { |p| p[:type] }

        expect(config_problem_types).not_to include("step_config_invalid")
        expect(config_problem_types).not_to include("element_config_invalid")
      end
    end

    context "case 4 — unknown action / unknown element type causes no double-reporting" do
      it "does not emit step_config_invalid for a step with an unknown action" do
        # unknown action is reported by the structured codegen failure.
        unknown_step_element = process_with_step(
          "s1", "totally_unknown_action_xyz",
          { "someField" => "value" }
        )
        config = linear_config(unknown_step_element)

        problems = problems_for(config)

        expect(problems.map { |p| p[:type] }).not_to include("step_config_invalid")
        expect(problems.map { |p| p[:type] }).to include("codegen_failed")
      end

      it "does not emit element_config_invalid for an element with an unknown type" do
        # unknown element type is reported by the structured codegen failure.
        unknown_type_el = element("unknown_1", "completely_unknown_type_xyz", "Mystery Box", {})
        config = linear_config(unknown_type_el)

        problems = problems_for(config)

        expect(problems.map { |p| p[:type] }).not_to include("element_config_invalid")
        expect(problems.map { |p| p[:type] }).to include("codegen_failed")
      end
    end

    context "case 5 — a generator whose validate_config raises is swallowed" do
      it "still returns an array and does not raise" do
        # Stub the registry to return a generator class whose validate_config raises
        exploding_gen_class = Class.new(CodeGenerators::BaseGenerator) do
          def self.registered_names; ["find_model"]; end
          def generate_body; "true"; end
          def validate_config(_cfg)
            raise RuntimeError, "generator internal error"
          end
        end

        registry = instance_double(CodeGenerators::GeneratorRegistry)
        allow(registry).to receive(:find_step_action).and_return(nil)
        allow(registry).to receive(:find_step_action).with("find_model").and_return(exploding_gen_class)
        allow(registry).to receive(:find_element_type).and_return(nil)
        allow(CodeGenerators::GeneratorRegistry).to receive(:instance).and_return(registry)

        bad_step_element = process_with_step("s1", "find_model", { "findStrategy" => "find" })
        config = linear_config(bad_step_element)

        result = nil
        expect { result = problems_for(config) }.not_to raise_error
        expect(result).to be_an(Array)
        # no step_config_invalid since the raise was swallowed
        expect(result.map { |p| p[:type] }).not_to include("step_config_invalid")
      end
    end

    context "case 6 — non-Hash config is coerced instead of silently skipped" do
      it "still validates a step whose config is a non-Hash (array) value" do
        # A malformed config (array, not hash) must not make the constructor or
        # validate_config raise into the per-item rescue and silently skip the
        # check — it is coerced to {} so missing required fields still surface.
        bad_step = { "id" => "s1", "action" => "find_model", "config" => %w[oops] }
        process_el = element("process_1", "process", "Do Work", { "steps" => [bad_step] })
        config = linear_config(process_el)

        problems = nil
        expect { problems = problems_for(config) }.not_to raise_error
        # find_model with empty config: STRATEGIES_REQUIRING_FIELD default still
        # produces no error, but the key point is the pass did not blow up and
        # the run completed (other phases still ran).
        expect(problems).to be_an(Array)
      end

      it "validates an element whose properties is a non-Hash value by coercing to {}" do
        # join with non-Hash properties → coerced to {}; wait_n not set, so no
        # requiredCount error, but the validator must not crash or skip via rescue.
        join_el = {
          "id" => "join_1", "type" => "join", "x" => 100, "y" => 100,
          "width" => 100, "height" => 45, "label" => "Merge",
          "properties" => "not a hash"
        }
        config = linear_config(join_el)

        expect { problems_for(config) }.not_to raise_error
      end

      it "passes through a step whose config is already a Hash without merging (with_hash_config pass-through)" do
        # with_hash_config returns item unchanged when item[config_key].is_a?(Hash)
        # Confirms no problem is raised and the result is a proper Array.
        good_step = { "id" => "s1", "action" => "find_model",
                      "config" => { "findStrategy" => "find", "resultVar" => "r" } }
        process_el = element("process_1", "process", "Do Work", { "steps" => [good_step] })
        config = linear_config(process_el)

        expect { problems_for(config) }.not_to raise_error
        expect(problems_for(config)).to be_an(Array)
      end
    end

    context "case 7 — step label is used in the problem message when present" do
      it "uses step label instead of action in the problem message" do
        bad_step_element = process_with_step(
          "s1", "find_model",
          { "findBy" => "nonsense_strategy" },
          label: "Find the user"
        )
        config = linear_config(bad_step_element)

        problems = problems_for(config)
        config_problem = problems.find { |p| p[:type] == "step_config_invalid" }

        expect(config_problem).to be_present
        expect(config_problem[:message]).to include("Find the user")
      end
    end
  end

end
