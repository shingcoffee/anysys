# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::Advance do
  let(:journey) { create(:journey, :launched) }
  let(:run) { JourneyRun.issue!(customer_id: journey.customer_id, user: nil, session: {}, journey: journey, current_step: "start").first }
  let(:entry) { instance_double(EntityEntry, id: 42) }

  def snapshot
    run.reload
    { step: run.current_step, status: run.status, records: run.records }
  end

  it "records the start record and moves to the relate step" do
    result = described_class.call(run: run, entry: entry, intent: nil)

    expect(result.kind).to eq(:step)
    expect(result.step.key).to eq("relate_1")
    expect(run.reload.current_step).to eq("relate_1")
    expect(run.records).to eq("start" => ["42"])
  end

  it "stays on a repeatable step when adding another" do
    run.update!(current_step: "relate_1")
    result = described_class.call(run: run, entry: instance_double(EntityEntry, id: 7), intent: "add_another")

    expect(result.kind).to eq(:step)
    expect(result.step.key).to eq("relate_1")
    expect(run.reload.current_step).to eq("relate_1")
    expect(run.records["relate_1"]).to eq(["7"])
  end

  it "moves on from a step that doesn't repeat even when asked to add another" do
    result = described_class.call(run: run, entry: entry, intent: "add_another")

    expect(result.step.key).to eq("relate_1")
  end

  it "treats an unknown intent as continue" do
    run.update!(current_step: "relate_1")

    expect(described_class.call(run: run, entry: entry, intent: { "x" => "add_another" }).kind).to eq(:finish)
  end

  it "finishes after the last working step and completes the run" do
    run.update!(current_step: "relate_1")
    result = described_class.call(run: run, entry: instance_double(EntityEntry, id: 8), intent: "continue")

    expect(result.kind).to eq(:finish)
    expect(result.step.key).to eq("finish")
    expect(run.reload).to be_completed
    expect(run.current_step).to eq("finish")
    expect(run.records["relate_1"]).to eq(["8"])
  end

  it "finishes a run whose current step no longer exists without recording" do
    run.update!(current_step: "gone")

    expect(described_class.call(run: run, entry: entry).kind).to eq(:finish)
    expect(run.reload).to be_completed
    expect(run.records).to eq({})
  end

  describe ".finishing?" do
    def step(key) = journey.steps_definition.steps.find { |candidate| candidate.key == key }

    def finishing?(key, run: nil, intent: nil) = described_class.finishing?(journey: journey, step: step(key), run: run, intent: intent)

    it "is false on the first step while later steps remain, even before the run exists" do
      expect(finishing?("start")).to be(false)
    end

    it "is false on a repeatable step when adding another" do
      run.record!("start", 42)

      expect(finishing?("relate_1", run: run, intent: "add_another")).to be(false)
    end

    it "is true on the last working step when not adding another" do
      run.record!("start", 42)

      expect([finishing?("relate_1", run: run), finishing?("relate_1", run: run, intent: "continue")]).to eq([true, true])
    end

    it "is true when every later step waits on a record the journey never got" do
      journey.update!(definition: { "steps" => [
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course", "optional" => true,
          "inputs" => { "student" => "start" } },
        { "key" => "dependent", "kind" => "relate", "action_key" => "student_add_note", "inputs" => { "enrolment" => "relate_1" } },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
      ] }.to_json)

      expect(finishing?("start")).to be(false)
      expect(finishing?("dependent", run: run)).to be(true)
    end
  end

  describe "a step that edits an earlier step's record" do
    before do
      journey.update!(definition: { "steps" => [
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        { "key" => "extra", "kind" => "create", "action_key" => "note_new", "optional" => true },
        { "key" => "review", "kind" => "update", "action_key" => "note_review", "record" => "extra" },
        { "key" => "confirm", "kind" => "update", "action_key" => "student_review", "record" => "start" },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
      ] }.to_json)
    end

    it "moves to it once its record exists, and records the record it edited under its own key" do
      described_class.call(run: run, entry: entry)
      expect(described_class.call(run: run.reload, entry: instance_double(EntityEntry, id: 5)).step.key).to eq("review")

      result = described_class.call(run: run.reload, entry: instance_double(EntityEntry, id: 5))

      expect(result.step.key).to eq("confirm")
      expect(run.reload.records).to eq("start" => ["42"], "extra" => ["5"], "review" => ["5"])
    end

    it "passes it over when the record it edits was skipped" do
      described_class.call(run: run, entry: entry)
      result = described_class.call(run: run.reload, entry: nil, intent: "skip")

      expect(result.step.key).to eq("confirm")
      expect(described_class.finishing?(journey: journey, step: journey.steps_definition.step("confirm"), run: run.reload, intent: nil))
        .to be(true)
    end
  end

  describe "skip" do
    def with_optional_steps(*working)
      steps = working + [{ "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }]
      journey.update!(definition: { "steps" => steps }.to_json)
    end

    it "skips an optional step without recording and moves on" do
      with_optional_steps(
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        { "key" => "note", "kind" => "create", "action_key" => "note_new", "optional" => true },
        { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "start" } }
      )
      described_class.call(run: run, entry: entry)
      result = described_class.call(run: run, entry: instance_double(EntityEntry, id: 9), intent: "skip")

      expect(result.kind).to eq(:step)
      expect(result.step.key).to eq("relate_1")
      expect(run.reload.current_step).to eq("relate_1")
      expect(run.records).to eq("start" => ["42"])
    end

    it "refuses to skip a required step and leaves the run unchanged" do
      before = snapshot
      result = described_class.call(run: run, entry: entry, intent: "skip")

      expect(result).to be_nil
      expect(snapshot).to eq(before)
    end

    it "passes later steps that needed a skipped record and finishes when none remain" do
      with_optional_steps(
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course",
          "inputs" => { "student" => "start" }, "optional" => true },
        { "key" => "dependent", "kind" => "relate", "action_key" => "student_add_note",
          "inputs" => { "enrolment" => "relate_1" } }
      )
      described_class.call(run: run, entry: entry)
      result = described_class.call(run: run.reload, entry: nil, intent: "skip")

      expect(result.kind).to eq(:finish)
      expect(result.step.key).to eq("finish")
      expect(run.reload).to be_completed
      expect(run.current_step).to eq("finish")
      expect(run.records).to eq("start" => ["42"])
    end

    it "finishes when the skipped step is the last working step" do
      with_optional_steps(
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course",
          "inputs" => { "student" => "start" }, "optional" => true }
      )
      described_class.call(run: run, entry: entry)
      result = described_class.call(run: run.reload, entry: nil, intent: "skip")

      expect(result.kind).to eq(:finish)
      expect(run.reload).to be_completed
      expect(run.records.keys).to eq(["start"])
    end
  end

  describe "steps an earlier step's processing leaves out" do
    before do
      journey.update!(definition: { "steps" => [
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        { "key" => "catering", "kind" => "create", "action_key" => "catering_new", "conditional" => true },
        { "key" => "dish", "kind" => "relate", "action_key" => "dish_new", "inputs" => { "order" => "catering" } },
        { "key" => "notes", "kind" => "create", "action_key" => "note_new" },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
      ] }.to_json)
    end

    it "passes over a conditional step the processing asked to leave out, and the steps that need its record" do
      result = described_class.call(run: run, entry: entry, skip: %w[catering])

      expect(result.step.key).to eq("notes")
      expect(run.reload.skipped).to eq(["catering"])
      expect(run.records).to eq("start" => ["42"])
    end

    it "keeps a step the journey doesn't let processing skip, and ignores steps that aren't later" do
      result = described_class.call(run: run, entry: entry, skip: %w[notes start dish missing])

      expect(result.step.key).to eq("catering")
      expect(run.reload.skipped).to eq([])
    end

    it "runs the conditional step when the processing asks for nothing" do
      expect(described_class.call(run: run, entry: entry).step.key).to eq("catering")
    end

    it "remembers what was left out for later moves and the finishing check" do
      described_class.call(run: run, entry: entry, skip: %w[catering])
      notes = journey.steps_definition.step("notes")

      expect(described_class.finishing?(journey: journey, step: notes, run: run.reload, intent: nil)).to be(true)
      run.update!(current_step: "start")
      expect(described_class.call(run: run, entry: entry).step.key).to eq("notes")
    end
  end
end
