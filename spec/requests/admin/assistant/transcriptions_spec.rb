# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin assistant transcriptions desktop API", type: :request do
  include_context "admin records"
  let(:path) { "/#{customer.id}/admin/assistant/transcriptions" }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: admin) }

  before do
    Authentication::Throttle.reset_store!
    clear_enqueued_jobs
  end

  after do
    Authentication::Throttle.reset_store!
    clear_enqueued_jobs
  end

  def dictation_upload
    upload = SpeechToTextAudioFixtures.upload
    Rack::Test::UploadedFile.new(upload[:io], upload[:content_type], original_filename: upload[:filename])
  end

  def dictation_params(**overrides)
    { audio: dictation_upload, duration_seconds: 3, conversation_id: conversation.id }.merge(overrides)
  end

  describe "POST /:cid/admin/assistant/transcriptions" do
    it "rejects a missing Bearer token even when a cookie session exists" do
      sign_in admin
      post path, params: { audio: audio_upload, duration_seconds: 3 }
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("invalid_token")
    end

    it "forbids a member token" do
      enable_ai_assistant!(customer)
      member = create(:user, :member, customer: customer)
      post path, params: { audio: audio_upload, duration_seconds: 3 },
           headers: bearer_headers(desktop_access_token_for(member))
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 202 with clip_id and defaults field_dom_id" do
      enable_ai_assistant!(customer)

      expect(OpenAI::Client).not_to receive(:new)
      post path, params: dictation_params,
           headers: bearer_headers(desktop_access_token_for(admin))

      expect(response).to have_http_status(:accepted)
      clip_id = response.parsed_body["clip_id"]
      expect(clip_id).to be_present
      clip = SpeechToText::Clip.find(clip_id)
      expect(clip.user).to eq(admin)
      expect(clip.customer).to eq(customer)
      expect(clip.field_dom_id).to eq("desktop")
      expect(clip.destination).to eq("assistant")
      expect(clip.conversation).to eq(conversation)
      expect(clip.status).to eq("pending")
      expect(clip.audio).to be_attached
      expect(SpeechToText::TranscribeJob).to have_been_enqueued.with(clip.id)
    end

    # This surface IS the assistant microphone, so the destination is fixed
    # server-side and a client cannot redirect its transcript elsewhere.
    it "ignores a client-supplied destination" do
      enable_ai_assistant!(customer)

      post path, params: dictation_params(destination: "field"),
           headers: bearer_headers(desktop_access_token_for(admin))

      expect(response).to have_http_status(:accepted)
      expect(SpeechToText::Clip.find(response.parsed_body["clip_id"]).destination).to eq("assistant")
    end

    it "forbids an admin from another tenant posting to this tenant's cid" do
      enable_ai_assistant!(customer)
      stranger = create(:user, :admin, customer: create(:customer))

      post path, params: { audio: audio_upload, duration_seconds: 3 },
           headers: bearer_headers(desktop_access_token_for(stranger))

      expect(response).to have_http_status(:forbidden)
      expect(SpeechToText::Clip.count).to eq(0)
    end

    it "enqueues when transcribe is on Aliyun and generation is on Cursor" do
      enable_ai_assistant_module!(customer)
      assign_mixed_ai_assistant_vendors!

      post path, params: dictation_params,
           headers: bearer_headers(desktop_access_token_for(admin))

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["clip_id"]).to be_present
    end

    it "pins dictation to the supplied owned thread even when another thread is newer" do
      target = conversation
      newer = create(:ai_assistant_conversation, customer: customer, user: admin, last_active_at: 1.minute.from_now)
      enable_ai_assistant!(customer)

      post path, params: dictation_params,
           headers: bearer_headers(desktop_access_token_for(admin))

      expect(response).to have_http_status(:accepted)
      clip = SpeechToText::Clip.find(response.parsed_body["clip_id"])
      expect(clip.conversation).to eq(target)
      expect(clip.conversation).not_to eq(newer)
    end

    [nil, "", "missing"].each do |conversation_id|
      it "rejects assistant dictation with conversation_id #{conversation_id.inspect} without creating a clip" do
        enable_ai_assistant!(customer)

        expect {
          post path, params: dictation_params(conversation_id: conversation_id),
               headers: bearer_headers(desktop_access_token_for(admin))
        }.not_to change(SpeechToText::Clip, :count)

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body).to eq("errors" => [I18n.t("ai_assistant.errors.conversation_not_found")])
        expect(SpeechToText::TranscribeJob).not_to have_been_enqueued
      end
    end

    it "rejects another user's thread in the same tenant" do
      enable_ai_assistant!(customer)
      other = create(:user, :admin, customer: customer)
      foreign = create(:ai_assistant_conversation, customer: customer, user: other)

      expect {
        post path, params: dictation_params(conversation_id: foreign.id),
             headers: bearer_headers(desktop_access_token_for(admin))
      }.not_to change(SpeechToText::Clip, :count)

      expect(response).to have_http_status(:not_found)
      expect(SpeechToText::TranscribeJob).not_to have_been_enqueued
    end

    it "rejects a thread in another tenant even when its user matches the token owner" do
      enable_ai_assistant!(customer)
      foreign = create(:ai_assistant_conversation, customer: create(:customer), user: admin)

      expect {
        post path, params: dictation_params(conversation_id: foreign.id),
             headers: bearer_headers(desktop_access_token_for(admin))
      }.not_to change(SpeechToText::Clip, :count)

      expect(response).to have_http_status(:not_found)
      expect(SpeechToText::TranscribeJob).not_to have_been_enqueued
    end

    it "rejects a deleted thread without falling back to the current thread" do
      enable_ai_assistant!(customer)
      stale_id = conversation.id
      conversation.destroy!
      create(:ai_assistant_conversation, customer: customer, user: admin)

      expect {
        post path, params: dictation_params(conversation_id: stale_id),
             headers: bearer_headers(desktop_access_token_for(admin))
      }.not_to change(SpeechToText::Clip, :count)

      expect(response).to have_http_status(:not_found)
      expect(SpeechToText::TranscribeJob).not_to have_been_enqueued
    end

    [false, :raise, :unsuccessful_job].each do |failure|
      it "returns 503 and the failed clip_id when job handoff is #{failure}" do
        enable_ai_assistant!(customer)
        case failure
        when :raise
          allow(SpeechToText::TranscribeJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue down")
        when :unsuccessful_job
          allow(SpeechToText::TranscribeJob).to receive(:perform_later)
            .and_return(instance_double(SpeechToText::TranscribeJob, successfully_enqueued?: false))
        else
          allow(SpeechToText::TranscribeJob).to receive(:perform_later).and_return(false)
        end

        expect {
          post path, params: dictation_params,
               headers: bearer_headers(desktop_access_token_for(admin))
        }.to change(SpeechToText::Clip, :count).by(1)

        expect(response).to have_http_status(:service_unavailable)
        clip = SpeechToText::Clip.find(response.parsed_body.fetch("clip_id"))
        expect(response.parsed_body).to eq(
          "clip_id" => clip.id,
          "error_code" => "enqueue_failed",
          "errors" => [I18n.t("speech_to_text.widget.generic_error")]
        )
        expect(clip).to have_attributes(customer_id: customer.id, user_id: admin.id, status: "failed", conversation_id: conversation.id)
        expect(clip.audio).not_to be_attached

        get "#{path}/#{clip.id}", headers: bearer_headers(desktop_access_token_for(admin))
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["status"]).to eq("failed")
        expect(response.parsed_body).not_to have_key("transcript")
      end
    end
  end

  describe "GET /:cid/admin/assistant/transcriptions/:id" do
    before { enable_ai_assistant!(customer) }

    it "returns pending status for the owner's clip" do
      clip = create(:speech_to_text_clip, customer: customer, user: admin)
      get "#{path}/#{clip.id}", headers: bearer_headers(desktop_access_token_for(admin))
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("id" => clip.id, "status" => "pending")
    end

    it "includes error_code and errors when failed" do
      clip = create(:speech_to_text_clip, :failed, customer: customer, user: admin, transcript: "Failed private text")
      get "#{path}/#{clip.id}", headers: bearer_headers(desktop_access_token_for(admin))
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("failed")
      expect(response.parsed_body["error_code"]).to eq("empty")
      expect(response.parsed_body["errors"]).to eq([ I18n.t("speech_to_text.widget.empty") ])
      expect(response.parsed_body).not_to have_key("transcript")
      expect(response.body).not_to include("Failed private text")
    end

    it "serializes processing status and the pinned assistant thread without raw text" do
      clip = create(:speech_to_text_clip, :assistant, customer: customer, user: admin,
                    conversation: conversation, status: "processing", transcript: "partial private text")

      get "#{path}/#{clip.id}", headers: bearer_headers(desktop_access_token_for(admin))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("id" => clip.id, "status" => "processing", "conversation_id" => conversation.id)
    end

    it "returns a completed field transcript only to the clip owner" do
      clip = create(:speech_to_text_clip, :succeeded, customer: customer, user: admin, transcript: "Dictated field text")

      get "#{path}/#{clip.id}", headers: bearer_headers(desktop_access_token_for(admin))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("id" => clip.id, "status" => "succeeded", "transcript" => "Dictated field text")
    end

    it "never returns a raw assistant transcript even if a persisted row contains one" do
      clip = create(:speech_to_text_clip, :assistant, :succeeded, customer: customer, user: admin,
                    conversation: conversation, transcript: "Private assistant text")

      get "#{path}/#{clip.id}", headers: bearer_headers(desktop_access_token_for(admin))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("id" => clip.id, "status" => "succeeded", "conversation_id" => conversation.id)
      expect(response.body).not_to include("Private assistant text")
    end

    it "returns 404 for another user's clip in the same tenant" do
      other = create(:user, :admin, customer: customer)
      clip = create(:speech_to_text_clip, :succeeded, customer: customer, user: other, transcript: "Other user's private text")
      get "#{path}/#{clip.id}", headers: bearer_headers(desktop_access_token_for(admin))
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq("not_found")
      expect(response.parsed_body).not_to have_key("transcript")
      expect(response.body).not_to include("Other user's private text")
    end

    # The tenant comes from the URL on this API, so the clip lookup must be
    # scoped to it as well as to the token owner.
    it "returns 404 for a clip belonging to another tenant" do
      other_customer = create(:customer)
      clip = create(:speech_to_text_clip, :succeeded, customer: other_customer,
                    user: create(:user, :admin, customer: other_customer), transcript: "Other tenant's private text")

      get "#{path}/#{clip.id}", headers: bearer_headers(desktop_access_token_for(admin))
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).not_to have_key("transcript")
      expect(response.body).not_to include("Other tenant's private text")
    end

    it "does not return an assistant thread id or transcript to another user" do
      other = create(:user, :admin, customer: customer)
      private_thread = create(:ai_assistant_conversation, customer: customer, user: other)
      clip = create(:speech_to_text_clip, :assistant, :succeeded, customer: customer, user: other,
                    conversation: private_thread, transcript: "Private assistant text")

      get "#{path}/#{clip.id}", headers: bearer_headers(desktop_access_token_for(admin))

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "not_found")
      expect(response.body).not_to include("Private assistant text")
    end

    it "returns 404 for a pruned clip id" do
      clip = create(:speech_to_text_clip, :succeeded, customer: customer, user: admin, transcript: "Pruned text")
      clip_id = clip.id
      clip.destroy!

      get "#{path}/#{clip_id}", headers: bearer_headers(desktop_access_token_for(admin))

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "not_found")
    end

    it "forbids reading a clip through another tenant's cid" do
      other_customer = create(:customer)
      clip = create(:speech_to_text_clip, customer: customer, user: admin)

      get "/#{other_customer.id}/admin/assistant/transcriptions/#{clip.id}",
          headers: bearer_headers(desktop_access_token_for(admin))
      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
    end

    it "rejects a cookie session" do
      clip = create(:speech_to_text_clip, customer: customer, user: admin)
      sign_in admin
      get "#{path}/#{clip.id}"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
