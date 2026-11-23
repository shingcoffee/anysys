# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::AiAssistant::Transcriptions", type: :request do
  include_context "admin records"

  before { enable_ai_assistant_module!(customer) }

  def path(cid = customer.id)
    "/#{cid}/admin/modules/ai_assistant/transcriptions"
  end

  def enqueue_success(clip_id: 42)
    clip = instance_double("SpeechToText::Clip", id: clip_id)
    SpeechToText::Activities::EnqueueTranscription::Result.new(
      success?: true,
      record: clip,
      http_status: :accepted,
      errors: []
    )
  end

  def enqueue_failure(http_status:, errors:, error_code: nil, clip: nil)
    SpeechToText::Activities::EnqueueTranscription::Result.new(
      success?: false,
      record: clip,
      http_status: http_status,
      errors: errors,
      error_code: error_code
    )
  end

  def dictation_upload
    upload = SpeechToTextAudioFixtures.upload
    Rack::Test::UploadedFile.new(upload[:io], upload[:content_type], original_filename: upload[:filename])
  end

  describe "POST create — auth guards" do
    let(:guard_path) { path }

    it_behaves_like "an admin-guarded request", :post
  end

  describe "POST create — admin, module enabled" do
    before { sign_in admin }

    it "returns 202 with clip_id on enqueue success" do
      allow(SpeechToText::Activities::EnqueueTranscription).to receive(:call)
        .and_return(enqueue_success(clip_id: 42))

      post path, params: { audio: audio_upload, field_dom_id: "entity_name" }, headers: json_headers

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to eq("clip_id" => 42)
    end

    it "passes current_customer and current_user, ignoring a client-supplied customer_id" do
      previous = ActionController::Parameters.action_on_unpermitted_parameters
      ActionController::Parameters.action_on_unpermitted_parameters = :raise
      other = create(:customer)
      expect(SpeechToText::Activities::EnqueueTranscription).to receive(:call) do |**kwargs|
        expect(kwargs[:customer]).to eq(customer)
        expect(kwargs[:user]).to eq(admin)
        expect(kwargs[:field_dom_id]).to eq("entity_name")
        expect(kwargs[:language]).to be_nil
        expect(kwargs[:duration_seconds]).to eq("12")
        expect(kwargs[:conversation_id]).to eq("123")
        enqueue_success
      end

      post path, params: {
        audio: audio_upload,
        field_dom_id: "entity_name",
        duration_seconds: "12",
        conversation_id: "123",
        customer_id: other.id
      }, headers: json_headers

      expect(response).to have_http_status(:accepted)
    ensure
      ActionController::Parameters.action_on_unpermitted_parameters = previous
    end

    it "forwards the widget's declared destination and pinned conversation for validation" do
      expect(SpeechToText::Activities::EnqueueTranscription).to receive(:call) do |**kwargs|
        expect(kwargs[:destination]).to eq("assistant")
        expect(kwargs[:conversation_id]).to eq("123")
        enqueue_success
      end

      post path, params: {
        audio: audio_upload,
        field_dom_id: "entity_name",
        destination: "assistant",
        conversation_id: "123"
      }, headers: json_headers

      expect(response).to have_http_status(:accepted)
    end

    it "forwards a nil destination when the widget declares none" do
      expect(SpeechToText::Activities::EnqueueTranscription).to receive(:call) do |**kwargs|
        expect(kwargs[:destination]).to be_nil
        expect(kwargs[:conversation_id]).to be_nil
        enqueue_success
      end

      post path, params: { audio: audio_upload, field_dom_id: "entity_name" }, headers: json_headers
      expect(response).to have_http_status(:accepted)
    end

    it "forwards an optional language param" do
      expect(SpeechToText::Activities::EnqueueTranscription).to receive(:call) do |**kwargs|
        expect(kwargs[:language]).to eq("zh-CN")
        enqueue_success
      end

      post path, params: {
        audio: audio_upload,
        field_dom_id: "entity_name",
        language: "zh-CN"
      }, headers: json_headers

      expect(response).to have_http_status(:accepted)
    end

    it "returns the activity http_status when the module is disabled" do
      allow(SpeechToText::Activities::EnqueueTranscription).to receive(:call)
        .and_return(enqueue_failure(http_status: :forbidden, errors: ["disabled"]))

      post path, params: { audio: audio_upload, field_dom_id: "entity_name" }, headers: json_headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq("errors" => ["disabled"])
    end

    it "returns the activity http_status when the vendor is unconfigured" do
      allow(SpeechToText::Activities::EnqueueTranscription).to receive(:call)
        .and_return(enqueue_failure(http_status: :unprocessable_entity, errors: ["unconfigured"]))

      post path, params: { audio: audio_upload, field_dom_id: "entity_name" }, headers: json_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("errors" => ["unconfigured"])
    end

    it "includes error_code when the activity reports too_long" do
      allow(SpeechToText::Activities::EnqueueTranscription).to receive(:call)
        .and_return(enqueue_failure(http_status: :unprocessable_entity, errors: ["too long"], error_code: "too_long"))

      post path, params: { audio: audio_upload, field_dom_id: "entity_name", duration_seconds: "999" },
           headers: json_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("errors" => ["too long"], "error_code" => "too_long")
    end

    it "includes clip_id when a failed activity retained a clip" do
      clip = create(:speech_to_text_clip, :failed, customer: customer, user: admin)
      allow(SpeechToText::Activities::EnqueueTranscription).to receive(:call)
        .and_return(enqueue_failure(http_status: 503, errors: [I18n.t("speech_to_text.widget.generic_error")],
                                   error_code: "enqueue_failed", clip: clip))

      post path, params: { audio: audio_upload, field_dom_id: "entity_name" }, headers: json_headers

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq(
        "clip_id" => clip.id,
        "errors" => [I18n.t("speech_to_text.widget.generic_error")],
        "error_code" => "enqueue_failed"
      )
    end
  end

  describe "POST create — real dictation handoff" do
    let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: admin) }
    let(:headers) { { "Accept" => "application/json" } }

    before do
      create(:ai_assistant_provider_settings)
      Authentication::Throttle.reset_store!
      clear_enqueued_jobs
      sign_in admin
    end

    after do
      Authentication::Throttle.reset_store!
      clear_enqueued_jobs
    end

    def dictation_params(**overrides)
      { audio: dictation_upload, field_dom_id: "assistant_composer", duration_seconds: 3,
        destination: "assistant", conversation_id: conversation.id }.merge(overrides)
    end

    it "attaches audio and enqueues the selected owned assistant thread" do
      selected = conversation
      create(:ai_assistant_conversation, customer: customer, user: admin, last_active_at: 1.minute.from_now)
      expect(OpenAI::Client).not_to receive(:new)

      post path, params: dictation_params, headers: headers

      expect(response).to have_http_status(:accepted)
      clip = SpeechToText::Clip.find(response.parsed_body.fetch("clip_id"))
      expect(clip).to have_attributes(customer_id: customer.id, user_id: admin.id, destination: "assistant", status: "pending")
      expect(clip.conversation).to eq(selected)
      expect(clip.audio).to be_attached
      expect(SpeechToText::TranscribeJob).to have_been_enqueued.with(clip.id)
    end

    it "keeps ordinary field dictation independent of a supplied assistant thread" do
      other = create(:user, :admin, customer: customer)
      foreign = create(:ai_assistant_conversation, customer: customer, user: other)

      post path, params: dictation_params(destination: "field", conversation_id: foreign.id), headers: headers

      expect(response).to have_http_status(:accepted)
      clip = SpeechToText::Clip.find(response.parsed_body.fetch("clip_id"))
      expect(clip).to have_attributes(destination: "field", conversation_id: nil, user_id: admin.id, customer_id: customer.id)
    end

    [nil, "", "missing"].each do |conversation_id|
      it "rejects assistant dictation with conversation_id #{conversation_id.inspect}" do
        expect {
          post path, params: dictation_params(conversation_id: conversation_id), headers: headers
        }.not_to change(SpeechToText::Clip, :count)

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body).to eq("errors" => [I18n.t("ai_assistant.errors.conversation_not_found")])
        expect(SpeechToText::TranscribeJob).not_to have_been_enqueued
      end
    end

    it "rejects another user's thread in the same tenant" do
      other = create(:user, :admin, customer: customer)
      foreign = create(:ai_assistant_conversation, customer: customer, user: other)

      expect {
        post path, params: dictation_params(conversation_id: foreign.id), headers: headers
      }.not_to change(SpeechToText::Clip, :count)

      expect(response).to have_http_status(:not_found)
      expect(SpeechToText::TranscribeJob).not_to have_been_enqueued
    end

    it "rejects another tenant's thread even when its user matches the session owner" do
      foreign = create(:ai_assistant_conversation, customer: create(:customer), user: admin)

      expect {
        post path, params: dictation_params(conversation_id: foreign.id), headers: headers
      }.not_to change(SpeechToText::Clip, :count)

      expect(response).to have_http_status(:not_found)
      expect(SpeechToText::TranscribeJob).not_to have_been_enqueued
    end

    it "rejects a thread deleted after validation without installing a clip in another thread" do
      selected = conversation
      create(:ai_assistant_conversation, customer: customer, user: admin, last_active_at: 1.minute.from_now)
      allow(SpeechToText::AudioProbe).to receive(:call).and_wrap_original do |original, **kwargs|
        original.call(**kwargs).tap { selected.destroy! }
      end

      expect {
        post path, params: dictation_params, headers: headers
      }.not_to change(SpeechToText::Clip, :count)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).not_to have_key("clip_id")
      expect(SpeechToText::TranscribeJob).not_to have_been_enqueued
    end

    it "returns 503 with the failed, purged clip when the queue refuses the upload" do
      allow(SpeechToText::TranscribeJob).to receive(:perform_later).and_return(false)

      post path, params: dictation_params, headers: headers

      expect(response).to have_http_status(:service_unavailable)
      clip = SpeechToText::Clip.find(response.parsed_body.fetch("clip_id"))
      expect(response.parsed_body["error_code"]).to eq("enqueue_failed")
      expect(clip).to have_attributes(status: "failed", conversation_id: conversation.id, user_id: admin.id, customer_id: customer.id)
      expect(clip.audio).not_to be_attached
    end

    it "rejects fake encoded audio even when its MIME is allowed" do
      upload = Rack::Test::UploadedFile.new(StringIO.new("fake-webm-bytes"), "audio/webm", original_filename: "clip.webm")

      expect {
        post path, params: dictation_params(audio: upload), headers: headers
      }.not_to change(SpeechToText::Clip, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error_code"]).to eq("invalid_audio")
      expect(response.parsed_body).not_to have_key("clip_id")
      expect(SpeechToText::TranscribeJob).not_to have_been_enqueued
    end
  end

  describe "POST create — cross-tenant" do
    it "forbids an admin of customer A posting to customer B's cid" do
      other = create(:customer)
      sign_in admin
      allow(SpeechToText::Activities::EnqueueTranscription).to receive(:call)

      post path(other.id), params: { audio: audio_upload, field_dom_id: "entity_name" },
           headers: json_headers

      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
      expect(SpeechToText::Activities::EnqueueTranscription).not_to have_received(:call)
    end
  end
end
