# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpeechToText::Activities::EnqueueTranscription do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }

  # A fresh IO per call — ActiveStorage consumes the stream, so a memoized one
  # would fail its integrity check on the second attach.
  def audio(size: nil)
    upload = SpeechToTextAudioFixtures.upload
    allow(upload[:io]).to receive(:size).and_return(size) if size
    upload
  end

  def enqueue(**overrides)
    described_class.call(
      customer: customer,
      user: user,
      audio: audio,
      field_dom_id: "entity_entry_title",
      duration_seconds: 5,
      **overrides
    )
  end

  before do
    Current.customer = customer
    enable_ai_assistant!(customer)
    Authentication::Throttle.reset_store!
  end

  after { Authentication::Throttle.reset_store! }

  it "creates a pending clip, attaches audio, enqueues TranscribeJob, and returns 202" do
    result = nil
    expect {
      result = enqueue
    }.to have_enqueued_job(SpeechToText::TranscribeJob)
    expect(result.success?).to eq(true)
    expect(result.http_status).to eq(202)
    expect(result.clip).to be_present
    expect(result.clip.status).to eq("pending")
    expect(result.clip.audio).to be_attached
    expect(result.clip.field_dom_id).to eq("entity_entry_title")
  end

  it "never constructs OpenAI::Client" do
    expect(OpenAI::Client).not_to receive(:new)
    enqueue
  end

  [false, :raise].each do |failure|
    it "retains a failed, purged clip when job enqueue returns #{failure}" do
      if failure == :raise
        allow(SpeechToText::TranscribeJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue down")
      else
        allow(SpeechToText::TranscribeJob).to receive(:perform_later).and_return(false)
      end

      result = enqueue
      expect(result).to have_attributes(success?: false, http_status: 503, error_code: "enqueue_failed")
      expect(result.clip.reload.status).to eq("failed")
      expect(result.clip.audio).not_to be_attached
    end
  end

  it "retains terminal state when purge fails, for scheduled cleanup" do
    allow(SpeechToText::TranscribeJob).to receive(:perform_later).and_return(false)
    allow_any_instance_of(ActiveStorage::Attached::One).to receive(:purge).and_raise(IOError, "storage down")

    result = enqueue
    expect(result.clip.reload.status).to eq("failed")
    expect(result.clip.audio).to be_attached
  end

  it "fails closed when the decoder is unavailable" do
    allow(SpeechToText::AudioProbe).to receive(:call).and_raise(SpeechToText::AudioProbe::Unavailable)
    result = enqueue
    expect(result).to have_attributes(http_status: 503, error_code: "audio_probe_unavailable")
    expect(SpeechToText::Clip.count).to eq(0)
  end

  it "returns 403 when the module is not enabled for the customer" do
    fm = FeatureModules::Module.find_by!(key: "ai_assistant")
    FeatureModules::CustomerAssignment.where(customer: customer, feature_module: fm).delete_all
    result = enqueue
    expect(result.success?).to eq(false)
    expect(result.http_status).to eq(403)
    expect(result.errors).to eq([I18n.t("ai_assistant.errors.module_disabled")])
  end

  it "returns 403 when no transcribe assignee is configured" do
    AiAssistant::ProviderSettings.update_all(transcribe_active: false)
    result = enqueue
    expect(result.http_status).to eq(403)
    expect(SpeechToText::Clip.count).to eq(0)
  end

  it "enqueues when only a transcribe assignee is configured" do
    AiAssistant::ProviderSettings.update_all(generation_active: false)
    expect(enqueue.http_status).to eq(202)
  end

  describe "rate limits" do
    # Regression: the limiter used Rails.cache#increment, which returns nil for
    # a missing key and does not create it on memory_store/solid_cache/
    # null_store — so the counter never seeded and the cap never fired in ANY
    # environment. These examples drive the real limiter, not a stub.
    let(:burst) { AiAssistant::Limits::BURST }
    let(:sustained) { AiAssistant::Limits::SUSTAINED }

    around do |example|
      travel_to(Time.utc(2026, 1, 1, 12, 0, 0)) { example.run }
    end

    def enqueue_burst(count = burst.limit)
      statuses = Array.new(count) { enqueue.http_status }
      travel(burst.period + 1.second)
      statuses
    end

    it "allows exactly BURST clips in a window and rejects the next one" do
      burst.limit.times do |i|
        expect(enqueue.http_status).to eq(202), "call #{i + 1} of #{burst.limit} should have been accepted"
      end

      over = enqueue
      expect(over.http_status).to eq(429)
      expect(over.errors.join).to include("recording too quickly")
      expect(SpeechToText::Clip.count).to eq(burst.limit)
    end

    it "allows exactly SUSTAINED clips an hour and rejects the next one" do
      (sustained.limit / burst.limit).times { expect(enqueue_burst).to all(eq(202)) }

      over = enqueue
      expect(over.http_status).to eq(429)
      expect(over.errors.join).to include("Too many transcriptions")
      expect(SpeechToText::Clip.count).to eq(sustained.limit)
    end

    it "counts per user, so one user cannot exhaust another's quota" do
      other = create(:user, :admin, customer: customer)
      burst.limit.times { enqueue }
      expect(enqueue.http_status).to eq(429)

      result = described_class.call(
        customer: customer, user: other, audio: audio,
        field_dom_id: "entity_entry_title", duration_seconds: 5
      )
      expect(result.http_status).to eq(202)
    end
  end

  it "returns 422 with error_code too_long when duration exceeds the tenant max" do
    result = enqueue(duration_seconds: 61)
    expect(result.http_status).to eq(422)
    expect(result.error_code).to eq("too_long")
    expect(result.errors.join).to include("too long")
    expect(SpeechToText::Clip.count).to eq(0)
  end

  it "returns 422 when duration_seconds is omitted" do
    result = enqueue(duration_seconds: nil)
    expect(result.http_status).to eq(422)
    expect(result.error_code).to eq("too_long")
  end

  it "caps tenant max_duration_seconds at 120" do
    fm = FeatureModules::Module.find_by!(key: "ai_assistant")
    assignment = FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: fm)
    assignment.update!(configuration: { "max_duration_seconds" => "999" }.to_json)
    result = enqueue(duration_seconds: 121)
    expect(result.http_status).to eq(422)
    expect(result.error_code).to eq("too_long")
  end

  it "accepts duration at the tenant max_duration_seconds" do
    fm = FeatureModules::Module.find_by!(key: "ai_assistant")
    assignment = FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: fm)
    assignment.update!(configuration: { "max_duration_seconds" => "90" }.to_json)
    result = enqueue(duration_seconds: 90)
    expect(result.success?).to eq(true)
  end

  it "returns 422 when audio is missing" do
    result = enqueue(audio: nil)
    expect(result.http_status).to eq(422)
    expect(result.clip).to be_nil
  end

  it "returns 422 when audio exceeds 25 MB" do
    result = enqueue(audio: audio(size: 25.megabytes + 1))
    expect(result.http_status).to eq(422)
    expect(result.errors.join).to include("too large")
  end

  it "returns 422 when field_dom_id is blank" do
    result = enqueue(field_dom_id: "")
    expect(result.http_status).to eq(422)
  end

  it "returns 422 when Content-Type is not an allowed audio type" do
    result = enqueue(audio: { io: StringIO.new("x"), filename: "x.txt", content_type: "text/plain" })
    expect(result.http_status).to eq(422)
  end

  it "returns 422 when the client omits the Content-Type entirely" do
    result = enqueue(audio: { io: StringIO.new("x"), filename: "clip.webm", content_type: nil })
    expect(result.http_status).to eq(422)
    expect(result.errors.join).to include("invalid")
    expect(SpeechToText::Clip.count).to eq(0)
  end

  describe "server-side duration enforcement" do
    it "rejects a real 61-second compressed clip claiming one second" do
      result = enqueue(audio: SpeechToTextAudioFixtures.upload(duration: 61), duration_seconds: 1)
      expect(result).to have_attributes(http_status: 422, error_code: "too_long")
      expect(SpeechToText::Clip.count).to eq(0)
    end

    it "rejects invalid encoded audio before creating a clip" do
      result = enqueue(audio: { io: StringIO.new("fake-audio"), filename: "clip.webm", content_type: "audio/webm" })
      expect(result).to have_attributes(http_status: 422, error_code: "invalid_audio")
      expect(SpeechToText::Clip.count).to eq(0)
    end
    def long_clip_bytes
      SpeechToText::AudioFormats.max_bytes_for(60, filename: "silence.flac", content_type: "audio/flac") + 1
    end

    it "rejects a clip whose size exceeds the tenant cap even when the client under-reports duration" do
      result = enqueue(audio: audio(size: long_clip_bytes), duration_seconds: 1)

      expect(result.http_status).to eq(422)
      expect(result.error_code).to eq("too_long")
      expect(SpeechToText::Clip.count).to eq(0)
    end

    it "accepts a clip that fits the byte ceiling implied by the tenant cap" do
      result = enqueue(audio: audio(size: long_clip_bytes - 2), duration_seconds: 1)
      expect(result.success?).to eq(true)
    end

    it "scales the ceiling with the tenant's configured cap" do
      fm = FeatureModules::Module.find_by!(key: "ai_assistant")
      assignment = FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: fm)
      assignment.update!(configuration: { "max_duration_seconds" => "120" }.to_json)

      result = enqueue(audio: audio(size: long_clip_bytes), duration_seconds: 1)
      expect(result.success?).to eq(true)
    end
  end

  describe "destination" do
    it "defaults to field so a plain dictate widget fills its own input" do
      expect(enqueue.clip.destination).to eq("field")
    end

    it "records an explicit assistant destination" do
      clip = enqueue(destination: "assistant", conversation_id: conversation.id).clip
      expect(clip).to have_attributes(destination: "assistant", conversation_id: conversation.id)
    end

    it "requires an explicit owned thread for assistant dictation" do
      expect(enqueue(destination: "assistant").http_status).to eq(404)
      other = create(:user, customer: customer)
      foreign = create(:ai_assistant_conversation, customer: customer, user: other)
      expect(enqueue(destination: "assistant", conversation_id: foreign.id).http_status).to eq(404)
      other_tenant = create(:customer)
      cross = create(:ai_assistant_conversation, customer: other_tenant, user: user)
      expect(enqueue(destination: "assistant", conversation_id: cross.id).http_status).to eq(404)
      expect(SpeechToText::Clip.count).to eq(0)
    end

    it "returns 404 if the authorized thread is deleted before clip installation" do
      target = conversation
      allow(SpeechToText::AudioProbe).to receive(:call).and_wrap_original do |original, **args|
        original.call(**args).tap { target.destroy! }
      end
      result = enqueue(destination: "assistant", conversation_id: target.id)
      expect(result.http_status).to eq(404)
      expect(SpeechToText::Clip.count).to eq(0)
      expect(SpeechToText::TranscribeJob).not_to have_been_enqueued
    end

    it "fails closed to field for an unknown destination" do
      expect(enqueue(destination: "somewhere_else").clip.destination).to eq("field")
    end
  end

  it "stores tenant language from CustomerAssignment when language is omitted" do
    fm = FeatureModules::Module.find_by!(key: "ai_assistant")
    assignment = FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: fm)
    assignment.update!(configuration: { "language" => "zh-CN" }.to_json)
    result = enqueue(language: nil)
    expect(result.clip.language).to eq("zh-CN")
  end
end
