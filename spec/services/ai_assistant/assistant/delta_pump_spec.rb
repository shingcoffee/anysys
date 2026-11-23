# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::DeltaPump do
  let(:conversation) { instance_double(AiAssistant::Conversation) }
  let(:publisher) { class_double(AiAssistant::Stream, broadcast_delta: nil) }
  # Monotonic clock stand-in: a mutable holder the injected lambda reads, so
  # coalescing windows are decided by the example rather than by wall time.
  let(:now) { { seconds: 100.0 } }
  let(:clock) { -> { now[:seconds] } }
  let(:pump) { described_class.new(conversation: conversation, publisher: publisher, clock: clock) }

  def advance(seconds)
    now[:seconds] += seconds
  end

  # The pump is fed raw vendor frames, so the prose it publishes is whatever
  # StreamingText can see in the partial document so far.
  def open_document(reply)
    %({"intent":"chat","reply":"#{reply})
  end

  describe "the first frame" do
    it "publishes as soon as there is prose to show" do
      pump.push(open_document("Hello"))

      expect(publisher).to have_received(:broadcast_delta).with(conversation, "Hello").once
    end

    it "publishes nothing while the document has not reached its reply" do
      pump.push('{"intent":"chat"')

      expect(publisher).not_to have_received(:broadcast_delta)
    end
  end

  describe "coalescing" do
    before { pump.push(open_document("Hello")) }

    it "withholds a frame below both the interval and the growth threshold" do
      pump.push(" there")

      expect(publisher).to have_received(:broadcast_delta).once
      expect(publisher).not_to have_received(:broadcast_delta).with(conversation, "Hello there")
    end

    it "publishes once the growth threshold is crossed" do
      pump.push("x" * described_class::MIN_GROWTH)

      expect(publisher).to have_received(:broadcast_delta)
        .with(conversation, "Hello#{"x" * described_class::MIN_GROWTH}")
    end

    it "publishes a trickle once the interval has elapsed" do
      advance(described_class::MIN_INTERVAL)
      pump.push(" there")

      expect(publisher).to have_received(:broadcast_delta).with(conversation, "Hello there")
    end

    it "keeps withholding just under the interval" do
      advance(described_class::MIN_INTERVAL - 0.01)
      pump.push(" there")

      expect(publisher).to have_received(:broadcast_delta).once
    end

    it "does not re-broadcast text that has not changed" do
      advance(10)
      pump.push('","entities":[]}')

      expect(publisher).to have_received(:broadcast_delta).once
    end
  end

  describe "#flush" do
    it "forces out what the last push withheld" do
      pump.push(open_document("Hello"))
      pump.push(" there")

      pump.flush

      expect(publisher).to have_received(:broadcast_delta).with(conversation, "Hello there")
    end

    it "publishes nothing when the last push already went out" do
      pump.push(open_document("Hello"))

      pump.flush

      expect(publisher).to have_received(:broadcast_delta).once
    end

    it "publishes nothing when no prose ever arrived" do
      pump.flush

      expect(publisher).not_to have_received(:broadcast_delta)
    end
  end

  describe "#begin_call" do
    before { pump.push(open_document("First answer")) }

    it "restarts the buffer so two documents are not spliced together" do
      pump.begin_call

      expect(pump.raw).to eq("")
    end

    it "publishes the new call's prose on its own, not appended to the old" do
      pump.begin_call
      advance(1)
      pump.push(open_document("Second answer"))

      expect(publisher).to have_received(:broadcast_delta).with(conversation, "Second answer")
      expect(publisher).not_to have_received(:broadcast_delta).with(conversation, "First answerSecond answer")
    end

    # A follow-on call that yields no prose must leave the previous preview on
    # screen rather than blanking it.
    it "keeps what was already published when the new call shows nothing" do
      pump.begin_call
      advance(1)
      pump.push('{"intent":"chat","reply":"')
      pump.flush

      expect(publisher).to have_received(:broadcast_delta).with(conversation, "First answer").once
      expect(publisher).not_to have_received(:broadcast_delta).with(conversation, "")
    end

    it "does not re-publish prose identical to what is already on screen" do
      pump.begin_call
      advance(1)
      pump.push(open_document("First answer"))
      pump.flush

      expect(publisher).to have_received(:broadcast_delta).once
    end
  end

  describe "with no conversation" do
    let(:pump) { described_class.new(conversation: nil, publisher: publisher, clock: clock) }

    it "accumulates without broadcasting" do
      pump.push(open_document("Hello"))
      advance(10)
      pump.push(" there")
      pump.flush

      expect(publisher).not_to have_received(:broadcast_delta)
      expect(pump.raw).to eq(open_document("Hello there"))
    end
  end

  describe "empty input" do
    it "ignores an empty chunk" do
      pump.push("")
      pump.push(nil)

      expect(pump.raw).to eq("")
      expect(publisher).not_to have_received(:broadcast_delta)
    end

    it "leaves an already published preview alone" do
      pump.push(open_document("Hello"))
      advance(10)
      pump.push("")

      expect(publisher).to have_received(:broadcast_delta).once
    end
  end

  describe "#call" do
    it "is the chunk sink the provider wrap invokes" do
      pump.call(open_document("Hello"))

      expect(publisher).to have_received(:broadcast_delta).with(conversation, "Hello")
    end
  end

  # Every scan walks the whole buffer and both the due? check and the publish
  # ask for it, so an unmemoised pump would be quadratic in reply length.
  describe "scan memoisation" do
    before { allow(AiAssistant::Assistant::StreamingText).to receive(:visible).and_call_original }

    it "scans once for the due? check and the publish of one push" do
      pump.push(open_document("Hello"))

      expect(AiAssistant::Assistant::StreamingText).to have_received(:visible).once
    end

    it "does not rescan an unchanged buffer on flush" do
      pump.push(open_document("Hello"))
      pump.flush
      pump.flush

      expect(AiAssistant::Assistant::StreamingText).to have_received(:visible).once
    end

    it "rescans once per push that grows the buffer" do
      pump.push(open_document("Hello"))
      pump.push(" there")
      pump.flush

      expect(AiAssistant::Assistant::StreamingText).to have_received(:visible).twice
    end
  end

  # Backstop: a lone surrogate must never reach Markdown, which raises on
  # invalid UTF-8 and would take the whole turn down with it.
  it "scrubs malformed bytes out of the preview" do
    pump.push(%({"intent":"chat","reply":"Hi \\ud83d\\ude00 there))

    expect(publisher).to have_received(:broadcast_delta) do |_conversation, text|
      expect(text).to be_valid_encoding
      expect(text).to eq("Hi 😀 there")
    end
  end
end
