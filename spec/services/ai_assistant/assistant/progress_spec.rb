# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Progress do
  let(:conversation) { instance_double(AiAssistant::Conversation) }
  let(:publisher) { class_double(AiAssistant::Stream, broadcast_progress: nil) }
  let(:progress) { described_class.new(conversation: conversation, publisher: publisher) }

  def states
    progress.steps.map { |step| [ step.key, step.state ] }
  end

  describe "#start" do
    it "opens a running step" do
      progress.start(:thinking)

      expect(states).to eq([ [ :thinking, :running ] ])
      expect(progress.running_key).to eq(:thinking)
    end

    it "returns itself so calls can be chained off the pipeline" do
      expect(progress.start(:thinking)).to be(progress)
    end

    it "records the detail it was given" do
      progress.start(:entity, detail: "Student")

      expect(progress.steps.last.detail).to eq("Student")
    end

    # Auto-closing the previous step keeps callers from having to pair every
    # begin with an end on every early return.
    it "closes the step already in flight as done" do
      progress.start(:thinking)
      progress.start(:entity)

      expect(states).to eq([ [ :thinking, :done ], [ :entity, :running ] ])
      expect(progress.running_key).to eq(:entity)
    end

    it "publishes the whole trace on every step" do
      progress.start(:thinking)
      progress.start(:catalog)

      expect(publisher).to have_received(:broadcast_progress).with(conversation, progress.steps).twice
    end

    it "refuses a key the panel has no label for" do
      expect { progress.start(:nonsense) }
        .to raise_error(ArgumentError, /unknown progress key nonsense/)
      expect(progress.steps).to be_empty
    end

    described_class::KEYS.each do |key|
      it "accepts the #{key} key and labels it for the reader's locale" do
        progress.start(key)

        expect(progress.steps.last.label).to eq(I18n.t("ai_assistant.assistant.progress.#{key}"))
        expect(progress.steps.last.label).to be_present
      end
    end
  end

  describe "#finish" do
    it "marks the running step done" do
      progress.start(:thinking)
      progress.finish

      expect(states).to eq([ [ :thinking, :done ] ])
      expect(progress.running_key).to be_nil
    end

    it "accepts an explicit terminal state" do
      progress.start(:verify)
      progress.finish(:failed)

      expect(states).to eq([ [ :verify, :failed ] ])
    end

    it "is safe to call with nothing running" do
      progress.finish

      expect(progress.steps).to be_empty
      expect(publisher).to have_received(:broadcast_progress).with(conversation, [])
    end

    it "leaves an already closed step alone" do
      progress.start(:thinking)
      progress.finish(:done)
      progress.finish(:failed)

      expect(states).to eq([ [ :thinking, :done ] ])
    end

    it "returns itself" do
      expect(progress.finish).to be(progress)
    end
  end

  describe "#fail!" do
    # Earlier steps stay intact so the reader can see how far the turn got.
    it "fails only the step in flight" do
      progress.start(:catalog)
      progress.start(:entity)
      progress.fail!

      expect(states).to eq([ [ :catalog, :done ], [ :entity, :failed ] ])
      expect(progress.running_key).to be_nil
    end

    it "returns itself" do
      progress.start(:catalog)

      expect(progress.fail!).to be(progress)
    end
  end

  describe described_class::Step do
    it "reports its own state" do
      running = described_class.new(key: :thinking, state: :running)
      done = described_class.new(key: :thinking, state: :done)
      failed = described_class.new(key: :thinking, state: :failed)

      expect(running).to be_running
      expect(running).not_to be_done
      expect(done).to be_done
      expect(failed).to be_failed
      expect(failed).not_to be_running
    end
  end

  # Stand-in for the pipeline stages that can run outside a live turn, so no
  # caller has to nil-check.
  describe described_class::Null do
    let(:null) { AiAssistant::Assistant::Progress.null }

    it "is what .null hands out" do
      expect(null).to be_a(described_class)
    end

    it "answers every message the real trace answers" do
      expect(null.start(:thinking)).to be(null)
      expect(null.start(:entity, detail: "Student")).to be(null)
      expect(null.finish).to be(null)
      expect(null.finish(:failed)).to be(null)
      expect(null.fail!).to be(null)
      expect(null.steps).to eq([])
      expect(null.running_key).to be_nil
    end

    it "accepts a key the real trace would reject, since it publishes nothing" do
      expect { null.start(:nonsense) }.not_to raise_error
    end

    it "never broadcasts" do
      allow(AiAssistant::Stream).to receive(:broadcast_progress)

      null.start(:thinking).finish

      expect(AiAssistant::Stream).not_to have_received(:broadcast_progress)
    end
  end
end
