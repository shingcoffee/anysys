# frozen_string_literal: true

require "rails_helper"

RSpec.describe JourneyRun do
  let(:customer) { create(:customer) }
  let(:session) { {} }

  it "stores only a digest and finds an anonymous run through the same session" do
    run, token = described_class.issue!(customer_id: customer.id, user: nil, session: session, state: { "a" => 1 })
    expect(run.token_digest).not_to eq(token)
    expect(run.token_digest).to eq(Digest::SHA256.hexdigest(token))
    expect(described_class.find_usable(token: token, customer_id: customer.id, user: nil, session: session)).to eq(run)
    expect(described_class.find_usable(token: token, customer_id: customer.id, user: nil, session: {})).to be_nil
  end

  it "ties a signed-in run to its user and customer" do
    user = create(:user, :admin, customer: customer)
    run, token = described_class.issue!(customer_id: customer.id, user: user, session: session)
    expect(session).to eq({})
    expect(described_class.find_usable(token: token, customer_id: customer.id, user: user, session: {})).to eq(run)
    expect(described_class.find_usable(token: token, customer_id: customer.id, user: create(:user, :admin, customer: customer), session: session)).to be_nil
    expect(described_class.find_usable(token: token, customer_id: create(:customer).id, user: user, session: session)).to be_nil
    expect(described_class.find_usable(token: token, customer_id: customer.id, user: nil, session: session)).to be_nil
  end

  it "ignores expired and completed runs" do
    run, token = described_class.issue!(customer_id: customer.id, user: nil, session: session)
    run.update_column(:expires_at, 1.minute.ago)
    expect(described_class.find_usable(token: token, customer_id: customer.id, user: nil, session: session)).to be_nil

    other, other_token = described_class.issue!(customer_id: customer.id, user: nil, session: session)
    other.completed!
    expect(described_class.find_usable(token: other_token, customer_id: customer.id, user: nil, session: session)).to be_nil
  end

  it "rejects malformed tokens" do
    [nil, "", "short", "x" * 101, ["a" * 30], { "t" => "a" * 30 }].each do |token|
      expect(described_class.find_usable(token: token, customer_id: customer.id, user: nil, session: session)).to be_nil
    end
  end

  it "keeps only the newest anonymous runs in the session" do
    digests = Array.new(JourneyRun::SESSION_LIMIT + 2) do
      described_class.issue!(customer_id: customer.id, user: nil, session: session).first.token_digest
    end
    expect(session[JourneyRun::SESSION_KEY]).to eq(digests.last(JourneyRun::SESSION_LIMIT))
  end

  it "remembers the steps a run left out once each, beside its records" do
    run, = described_class.issue!(customer_id: customer.id, user: nil, session: session, state: { "records" => { "start" => ["1"] } })
    expect(run.skipped).to eq([])

    run.skip!(%w[catering])
    run.skip!([:catering, "notes"])
    expect { run.skip!([]) }.not_to(change { run.reload.updated_at })

    expect(run.reload.skipped).to eq(%w[catering notes])
    expect(run.records).to eq("start" => ["1"])
  end

  it "reads no skipped steps from malformed state" do
    [{ "skipped" => { "a" => 1 } }, { "skipped" => "catering" }, []].each do |state|
      run, = described_class.issue!(customer_id: customer.id, user: nil, session: session, state: state)
      expect(run.skipped).to eq([])
    end
  end

  describe "#bindings_for" do
    let(:page) { instance_double(Page, id: 7, action_key: "student_add_course") }

    it "is empty without a journey or pinned inputs" do
      run, = described_class.issue!(customer_id: customer.id, user: nil, session: session,
                                    state: { "records" => { "start" => ["3"] } })
      expect(run.bindings_for(page)).to eq({})
    end

    it "fills only the pinned page's locked inputs from a run without a journey" do
      run, token = described_class.pin!(customer_id: customer.id, user: nil, session: session, page: page, inputs: { "student" => 42 })

      expect(run.journey).to be_nil
      expect(described_class.find_usable(token: token, customer_id: customer.id, user: nil, session: session)).to eq(run)
      expect(run.bindings_for(page)).to eq("student" => "42")
      expect(run.bindings_for(instance_double(Page, id: 8, action_key: "student_add_course"))).to eq({})
    end

    it "keeps the pinned inputs through a refused submit's retry" do
      run, = described_class.pin!(customer_id: customer.id, user: nil, session: session, page: page, inputs: { "student" => "42" })
      Pages::SubmissionRetry.store(run: run, page: page, values: { "status" => "x" }, field_errors: {}, customer_id: customer.id,
                                   user: nil, session: session)
      Pages::SubmissionRetry.take(run.reload, page)

      expect(run.reload.bindings_for(page)).to eq("student" => "42")
    end

    it "ignores malformed pinned state" do
      [{ JourneyRun::PINNED => "x" }, { JourneyRun::PINNED => { "page_id" => "7", "inputs" => [] } }].each do |state|
        run, = described_class.issue!(customer_id: customer.id, user: nil, session: session, state: state)
        expect(run.bindings_for(page)).to eq({})
      end
    end
  end

  describe "journey runs" do
    let(:journey) { create(:journey, customer: customer) }

    def journey_run(step, state: {})
      described_class.issue!(customer_id: customer.id, user: nil, session: session, state: state,
                             journey: journey, current_step: step).first
    end

    it "records each step's records once, newest last" do
      run = journey_run("start")
      run.record!(:start, 5)
      run.record!("relate_1", 7)
      run.record!("relate_1", 8)
      run.record!("relate_1", 7)

      expect(run.reload.records).to eq("start" => ["5"], "relate_1" => %w[7 8])
      expect(journey_run("start").records).to eq({})
    end

    it "keeps only a repeating step's most recent ids" do
      run = journey_run("relate_1")
      (1..(JourneyRun::RECORDS_PER_STEP + 2)).each { |id| run.record!("relate_1", id) }

      ids = run.reload.records["relate_1"]
      expect(ids.size).to eq(JourneyRun::RECORDS_PER_STEP)
      expect([ids.first, ids.last]).to eq(["3", (JourneyRun::RECORDS_PER_STEP + 2).to_s])
    end

    it "binds the current step's inputs to the latest record of their source step" do
      run = journey_run("relate_1")
      expect(run.bindings_for(instance_double(Page, action_key: "student_add_course"))).to eq({})

      run.record!("start", 5)
      run.record!("start", 6)
      expect(run.bindings_for(instance_double(Page, action_key: "student_add_course"))).to eq("student" => "6")
      expect(run.bindings_for(instance_double(Page, action_key: "student_new"))).to eq({})
    end

    it "binds nothing on an unknown step and ignores any handover" do
      run = journey_run("gone", state: { "handover" => { "page_id" => 7, "bindings" => { "student" => "3" } } })
      expect(run.bindings_for(instance_double(Page, id: 7, action_key: "student_add_course"))).to eq({})
    end

    it "refuses a journey from another customer" do
      foreign = create(:journey, customer: create(:customer))
      expect do
        described_class.issue!(customer_id: customer.id, user: nil, session: session, journey: foreign, current_step: "start")
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "reads no records from a non-object state" do
      run = journey_run("start")
      run.update_column(:state, "[1]")
      expect(run.reload.records).to eq({})
    end
  end
end
