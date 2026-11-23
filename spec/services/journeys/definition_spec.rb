# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::Definition do
  def definition(steps) = described_class.new("steps" => steps)

  let(:valid_steps) do
    [
      { "key" => "start", "kind" => "create", "action_key" => "student_new" },
      { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "start" }, "repeat" => true },
      { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
    ]
  end

  it "accepts a create, a repeatable relate and a record finish" do
    expect(definition(valid_steps)).to be_valid
    expect(definition(valid_steps).next_after("start").key).to eq("relate_1")
  end

  it "requires the journey to start by creating a record or from an existing one" do
    steps = valid_steps.dup.tap { |list| list[0] = list[0].merge("kind" => "relate", "inputs" => { "x" => "y" }) }
    expect(definition(steps).errors).to include(I18n.t("journeys.definition.errors.start_invalid"))
  end

  describe "a journey started from an existing record" do
    let(:record_steps) do
      [
        { "key" => "record", "kind" => "record", "entity_id" => "12" },
        { "key" => "courses", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "record" }, "repeat" => true },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "record" } }
      ]
    end

    it "accepts a record start whose record later steps fill from and the finish opens" do
      parsed = definition(record_steps)

      expect(parsed).to be_valid
      expect(parsed.record_start.key).to eq("record")
      expect(parsed.record_start.entity_id).to eq("12")
      expect(parsed.page_steps.map(&:key)).to eq(%w[courses])
      expect(parsed.first_page_step.key).to eq("courses")
      expect(parsed.action_keys).to eq(%w[student_add_course])
      expect(parsed.record_start).to be_record
      expect(parsed.record_start).not_to be_page
      expect(parsed.to_h["steps"].first).to eq("key" => "record", "kind" => "record", "entity_id" => "12",
                                               "inputs" => {}, "repeat" => false, "optional" => false)
    end

    it "has no record start or entity when it starts by creating" do
      parsed = definition(valid_steps)

      expect(parsed.record_start).to be_nil
      expect(parsed.first_page_step.key).to eq("start")
      expect(parsed.first_step.entity_id).to be_nil
    end

    it "needs a page step after the record" do
      expect(definition([record_steps.first, record_steps.last]).errors)
        .to include(I18n.t("journeys.definition.errors.record_needs_page"))
    end

    it "only takes a record step first, with a record type id" do
      late = [valid_steps.first, record_steps.first.merge("key" => "again"), valid_steps.last]
      expect(definition(late).errors).to include(I18n.t("journeys.definition.errors.record_first_only", step: "again"))

      %w[0 abc].push(nil).each do |entity_id|
        steps = record_steps.dup.tap { |list| list[0] = list[0].merge("entity_id" => entity_id) }
        expect(definition(steps).errors).to include(I18n.t("journeys.definition.errors.record_entity_invalid", step: "record"))
      end
    end

    describe "a start condition" do
      def with_when(condition) = definition(record_steps.dup.tap { |list| list[0] = list[0].merge("when" => condition) })
      def error(key, step: "record") = I18n.t("journeys.definition.errors.#{key}", step: step)
      def entry(data) = instance_double(EntityEntry, data_json: data)

      it "accepts a field and its listed values, and round-trips them" do
        parsed = with_when("field" => "status", "in" => %w[Submitted Resubmitted], "extra" => "dropped")

        expect(parsed).to be_valid
        expect(parsed.record_start.when).to eq("field" => "status", "in" => %w[Submitted Resubmitted])
        expect(parsed.to_h["steps"].first["when"]).to eq("field" => "status", "in" => %w[Submitted Resubmitted])
        expect(described_class.new(parsed.to_h).to_h).to eq(parsed.to_h)
        expect(definition(record_steps).to_h["steps"].first).not_to have_key("when")
      end

      it "needs a field slug and a non-empty list of non-blank values" do
        expect(with_when("field" => "Status!", "in" => ["A"]).errors).to eq([error(:when_field_invalid)])
        expect(with_when("field" => 7, "in" => ["A"]).errors).to eq([error(:when_field_invalid)])
        expect(with_when("in" => ["A"]).errors).to eq([error(:when_field_invalid)])
        expect(with_when("status").errors).to eq([error(:when_field_invalid)])
        [nil, [], [""], ["  "], [3], "Submitted"].each do |values|
          expect(with_when("field" => "status", "in" => values).errors).to eq([error(:when_values_invalid)])
        end
      end

      it "is only for the record a journey starts from" do
        steps = record_steps.dup.tap { |list| list[1] = list[1].merge("when" => { "field" => "status", "in" => ["A"] }) }

        expect(definition(steps).errors).to eq([error(:when_record_only, step: "courses")])
      end

      it "offers the journey only from a record whose stored value is listed" do
        start = with_when("field" => "status", "in" => %w[Submitted 2]).record_start

        expect(start.admits?(entry("status" => "Submitted"))).to be(true)
        expect(start.admits?(entry("status" => 2))).to be(true)
        expect(start.admits?(entry("status" => %w[Draft Submitted]))).to be(true)
        expect(start.admits?(entry("status" => "Draft"))).to be(false)
        expect(start.admits?(entry({}))).to be(false)
        expect(start.admits?(nil)).to be(false)
        expect(with_when("field" => "status", "in" => "Submitted").record_start.admits?(entry("status" => "Submitted"))).to be(false)
        expect(with_when("junk").record_start.admits?(entry("status" => "Submitted"))).to be(false)
        expect(definition(record_steps).record_start.admits?(nil)).to be(true)
      end
    end
  end

  describe "a step that edits an earlier step's record" do
    let(:update_steps) do
      [
        { "key" => "record", "kind" => "record", "entity_id" => "12" },
        { "key" => "review", "kind" => "update", "action_key" => "application_review", "record" => "record" },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "record" } }
      ]
    end

    it "may follow the start record straight away, and round-trips the record it edits" do
      parsed = definition(update_steps)

      expect(parsed).to be_valid
      review = parsed.step("review")
      expect(review).to be_update
      expect(review).to be_page
      expect(review.record).to eq("record")
      expect(review.needs).to eq(%w[record])
      expect(parsed.first_page_step).to eq(review)
      expect(parsed.to_h["steps"].second).to eq("key" => "review", "kind" => "update", "action_key" => "application_review",
                                                "record" => "record", "inputs" => {}, "repeat" => false, "optional" => false)
      expect(described_class.new(parsed.to_h).to_h).to eq(parsed.to_h)
    end

    it "edits a record a create or relate step saved, and may be skipped" do
      steps = valid_steps.first(2) + [
        { "key" => "review", "kind" => "update", "action_key" => "enrolment_review", "record" => "relate_1", "optional" => true },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
      ]
      parsed = definition(steps)

      expect(parsed).to be_valid
      expect(parsed.skippable?(parsed.step("review"))).to be(true)
    end

    it "needs an earlier record step, create, relate or update to name" do
      ["", "finish", "later", "review", nil].each do |source|
        steps = update_steps.dup.tap { |list| list[1] = list[1].merge("record" => source) }
        expect(definition(steps).errors).to include(I18n.t("journeys.definition.errors.update_record_invalid", step: "review"))
      end

      user_first = [{ "key" => "user", "kind" => "user" }, valid_steps.first,
                    update_steps.second.merge("record" => "user"), valid_steps.last]
      expect(definition(user_first).errors).to eq([I18n.t("journeys.definition.errors.update_record_invalid", step: "review")])
    end

    it "can't repeat or open a journey" do
      repeating = update_steps.dup.tap { |list| list[1] = list[1].merge("repeat" => true) }
      expect(definition(repeating).errors).to eq([I18n.t("journeys.definition.errors.repeat_relate_only", step: "review")])

      opening = [update_steps.second, update_steps.last.merge("target" => { "kind" => "page", "action_key" => "thanks" })]
      expect(definition(opening).errors).to include(I18n.t("journeys.definition.errors.start_invalid"))
    end

    it "is skipped with the optional step whose record it edits" do
      steps = valid_steps.first(1) + [
        { "key" => "extra", "kind" => "create", "action_key" => "note_new", "optional" => true },
        { "key" => "review", "kind" => "update", "action_key" => "note_review", "record" => "extra" },
        valid_steps.last
      ]
      parsed = definition(steps)

      expect(parsed).to be_valid
      expect(parsed.skippable?(parsed.step("review"))).to be(true)
      expect(parsed.skippable?(parsed.first_step)).to be(false)
    end
  end

  describe "a journey that opens by creating a user account" do
    let(:user_steps) do
      [
        { "key" => "user", "kind" => "user" },
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "start" }, "repeat" => true },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
      ]
    end

    it "accepts a user step followed by the create step its account is linked to" do
      parsed = definition(user_steps)

      expect(parsed).to be_valid
      expect(parsed.user_start.key).to eq("user")
      expect(parsed.user_start).to be_user
      expect(parsed.user_start).not_to be_page
      expect(parsed.account_step.key).to eq("start")
      expect(parsed.page_steps.map(&:key)).to eq(%w[start relate_1])
      expect(parsed.progress_steps.map(&:key)).to eq(%w[user start relate_1])
      expect(parsed.action_keys).to eq(%w[student_new student_add_course])
      expect(parsed.record_start).to be_nil
    end

    it "has no user start or account step otherwise" do
      parsed = definition(valid_steps)

      expect(parsed.user_start).to be_nil
      expect(parsed.account_step).to be_nil
      expect(parsed.progress_steps.map(&:key)).to eq(%w[start relate_1])
    end

    it "needs a create step right after the user step" do
      relate_next = [user_steps.first, user_steps.third.merge("inputs" => { "student" => "user" }), user_steps.last]
      expect(definition(relate_next).errors).to include(I18n.t("journeys.definition.errors.user_needs_create"))
      expect(definition([user_steps.first, user_steps.last]).errors).to include(I18n.t("journeys.definition.errors.user_needs_create"))
    end

    it "only takes a user step first" do
      late = [valid_steps.first, { "key" => "account", "kind" => "user" }, valid_steps.last]
      expect(definition(late).errors).to include(I18n.t("journeys.definition.errors.user_first_only", step: "account"))
    end

    it "is no record source: later steps can't fill from it or finish on it" do
      fill = user_steps.dup.tap { |list| list[2] = list[2].merge("inputs" => { "student" => "user" }) }
      expect(definition(fill).errors).to include(I18n.t("journeys.definition.errors.input_source_invalid", step: "relate_1"))

      finish = user_steps.dup.tap { |list| list[3] = list[3].merge("target" => { "kind" => "record", "step" => "user" }) }
      expect(definition(finish).errors).to include(I18n.t("journeys.definition.errors.finish_record_invalid"))
    end
  end

  it "requires exactly one finish at the end" do
    expect(definition(valid_steps.first(2)).errors).to include(I18n.t("journeys.definition.errors.finish_last"))
  end

  it "only lets relate steps repeat" do
    steps = valid_steps.dup.tap { |list| list[0] = list[0].merge("repeat" => true) }
    expect(definition(steps).errors.join).to include(I18n.t("journeys.definition.errors.repeat_relate_only", step: "start"))
  end

  it "only takes records from earlier steps" do
    steps = valid_steps.dup.tap { |list| list[1] = list[1].merge("inputs" => { "student" => "finish" }) }
    expect(definition(steps).errors.join).to include(I18n.t("journeys.definition.errors.input_source_invalid", step: "relate_1"))
  end

  it "rejects a record finish that points at no earlier step" do
    steps = valid_steps.dup.tap { |list| list[2] = list[2].merge("target" => { "kind" => "record", "step" => "nope" }) }
    expect(definition(steps).errors).to include(I18n.t("journeys.definition.errors.finish_record_invalid"))
  end

  it "accepts a page finish with a valid action key and rejects one without" do
    page_finish = valid_steps.dup.tap { |list| list[2] = list[2].merge("target" => { "kind" => "page", "action_key" => "thanks" }) }
    expect(definition(page_finish)).to be_valid

    page_finish[2] = page_finish[2].merge("target" => { "kind" => "page", "action_key" => "" })
    expect(definition(page_finish).errors).to include(I18n.t("journeys.definition.errors.finish_page_invalid"))

    page_finish[2] = page_finish[2].merge("target" => nil)
    expect(definition(page_finish).errors).to include(I18n.t("journeys.definition.errors.finish_target_invalid"))
  end

  it "flags short, duplicate-keyed, mis-keyed and page-less steps" do
    expect(definition([]).errors).to include(I18n.t("journeys.definition.errors.too_short"))

    duplicate = valid_steps.dup.tap { |list| list[1] = list[1].merge("key" => "start") }
    expect(definition(duplicate).errors).to include(I18n.t("journeys.definition.errors.duplicate_keys"))

    broken = valid_steps.dup.tap { |list| list[1] = list[1].merge("key" => "Bad Key", "kind" => "jump", "action_key" => nil, "inputs" => {}) }
    errors = definition(broken).errors
    expect(errors).to include(I18n.t("journeys.definition.errors.key_invalid", step: "Bad Key"),
                              I18n.t("journeys.definition.errors.kind_invalid", step: "Bad Key"),
                              I18n.t("journeys.definition.errors.action_key_invalid", step: "Bad Key"))

    no_input = valid_steps.dup.tap { |list| list[1] = list[1].merge("inputs" => {}, "label" => "Courses") }
    expect(definition(no_input).errors).to include(I18n.t("journeys.definition.errors.relate_needs_input", step: "Courses"))
  end

  it "accepts a mid-journey create step that locks nothing" do
    steps = [
      valid_steps.first,
      { "key" => "note", "kind" => "create", "action_key" => "note_new" },
      valid_steps.last
    ]
    expect(definition(steps)).to be_valid
  end

  it "does not let the first step be skipped" do
    steps = valid_steps.dup.tap { |list| list[0] = list[0].merge("optional" => true) }
    expect(definition(steps).errors).to include(I18n.t("journeys.definition.errors.optional_start", step: "start"))
  end

  it "does not finish on a record from an optional step" do
    steps = valid_steps.dup.tap do |list|
      list[1] = list[1].merge("optional" => true)
      list[2] = list[2].merge("target" => { "kind" => "record", "step" => "relate_1" })
    end
    expect(definition(steps).errors).to include(I18n.t("journeys.definition.errors.finish_record_optional"))
  end

  it "does not finish on a record that depends on a skipped step" do
    steps = [
      valid_steps.first,
      { "key" => "opt", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "start" }, "optional" => true },
      { "key" => "dep", "kind" => "relate", "action_key" => "student_add_note", "inputs" => { "enrolment" => "opt" } },
      { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "dep" } }
    ]
    parsed = definition(steps)
    expect(parsed.errors).to include(I18n.t("journeys.definition.errors.finish_record_optional"))
    expect(parsed.skippable?(parsed.step("opt"))).to be(true)
    expect(parsed.skippable?(parsed.step("dep"))).to be(true)
    expect(parsed.skippable?(parsed.first_step)).to be(false)
  end

  it "treats a step as skippable when it is optional or needs a skippable record" do
    steps = valid_steps.dup.tap { |list| list[1] = list[1].merge("optional" => true) }
    parsed = definition(steps)
    expect(parsed.skippable?(parsed.step("relate_1"))).to be(true)
    expect(parsed.skippable?(parsed.first_step)).to be(false)
    expect(parsed).to be_valid
  end

  describe "a step an earlier step's processing may leave out" do
    def error(key, step) = I18n.t("journeys.definition.errors.#{key}", step: step)

    it "keeps the flag, round-trips it and counts the step as skippable" do
      steps = valid_steps.dup.tap { |list| list[1] = list[1].merge("conditional" => "1") }
      parsed = definition(steps)

      expect(parsed.step("relate_1")).to be_conditional
      expect(parsed.skippable?(parsed.step("relate_1"))).to be(true)
      expect(parsed.to_h["steps"][1]["conditional"]).to be(true)
      expect(described_class.new(parsed.to_h).to_h).to eq(parsed.to_h)
      expect(parsed).to be_valid
    end

    it "drops a false flag" do
      steps = valid_steps.dup.tap { |list| list[1] = list[1].merge("conditional" => "0") }
      parsed = definition(steps)

      expect(parsed.step("relate_1")).not_to be_conditional
      expect(parsed.to_h["steps"][1]).not_to have_key("conditional")
    end

    it "refuses the flag on the first step, which no earlier processing runs before" do
      steps = valid_steps.dup.tap { |list| list[0] = list[0].merge("conditional" => true) }

      expect(definition(steps).errors).to include(error(:conditional_first, "start"))
    end

    it "refuses the flag on a finish step" do
      steps = valid_steps.dup.tap { |list| list[2] = list[2].merge("conditional" => true) }

      expect(definition(steps).errors).to include(error(:conditional_page_only, "finish"))
    end
  end

  it "exposes a stripped finish message" do
    with_message = valid_steps.dup.tap do |list|
      list[2] = list[2].merge("target" => { "kind" => "record", "step" => "start", "message" => "  Thanks  " })
    end
    expect(definition(with_message).finish_message).to eq("Thanks")
    expect(definition(valid_steps).finish_message).to be_nil
  end

  it "parses JSON, survives malformed input and round-trips through to_h" do
    parsed = described_class.new({ "steps" => valid_steps }.to_json)
    expect(parsed.steps.map(&:key)).to eq(%w[start relate_1 finish])
    expect(parsed.first_step.key).to eq("start")
    expect(parsed.finish.key).to eq("finish")
    expect(parsed.step(:relate_1).repeat).to be(true)
    expect(parsed.step(:relate_1).optional).to be(false)
    expect(parsed.action_keys).to eq(%w[student_new student_add_course])
    expect(parsed.next_after("finish")).to be_nil
    expect(parsed.next_after("nope")).to be_nil
    expect(described_class.new(parsed.to_h).to_h).to eq(parsed.to_h)
    expect(parsed.to_h["steps"].first).to eq("key" => "start", "kind" => "create", "action_key" => "student_new",
                                             "inputs" => {}, "repeat" => false, "optional" => false)

    expect(described_class.new("{not json").steps).to eq([])
    expect(described_class.new(nil).steps).to eq([])
    expect(described_class.new("steps" => ["junk", 3]).steps).to eq([])
    expect(described_class.new("[1, 2]").steps).to eq([])
    expect(described_class.new([[1, 2, 3]]).steps).to eq([])
    expect(described_class.blank.to_h).to eq("steps" => [])
  end

  it "labels a step by its label, falling back to its key" do
    labelled = definition([valid_steps.first.merge("label" => "  Register  ")]).first_step
    expect(labelled.display_label).to eq("Register")
    expect(definition(valid_steps).first_step.display_label).to eq("start")
  end
end
