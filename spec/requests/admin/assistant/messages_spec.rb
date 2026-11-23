# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin assistant messages desktop API", type: :request do
  include_context "admin records"
  let(:path) { "/#{customer.id}/admin/assistant/messages" }

  def bearer_get(token, request_path = path, extra_headers: {})
    get request_path, headers: bearer_headers(token, extra_headers)
  end

  def bearer_post(token, body:, request_path: path)
    post request_path,
         params: { body: body }.to_json,
         headers: bearer_headers(token, "CONTENT_TYPE" => "application/json")
  end

  describe "GET /:cid/admin/assistant/messages" do
    it "rejects a missing Bearer token even when a cookie session exists" do
      sign_in admin
      get path
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("invalid_token")
    end

    it "rejects an invalid token" do
      bearer_get("not-a-token")
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("invalid_token")
    end

    it "forbids a member token" do
      member = create(:user, :member, customer: customer)
      bearer_get(desktop_access_token_for(member))
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("access_denied")
    end

    it "forbids a same-role admin from another tenant" do
      other = create(:customer)
      stranger = create(:user, :admin, customer: other)
      bearer_get(desktop_access_token_for(stranger))
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 403 when the module is off" do
      create(:ai_assistant_provider_settings)
      bearer_get(desktop_access_token_for(admin))
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["errors"]).to include(I18n.t("ai_assistant.errors.module_disabled"))
    end

    it "returns 403 unconfigured when only a transcribe assignee is configured" do
      enable_ai_assistant_module!(customer)
      create(:ai_assistant_provider_settings, transcribe_active: true, generation_active: false)

      bearer_get(desktop_access_token_for(admin))

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["errors"]).to include(I18n.t("ai_assistant.errors.unconfigured"))
    end

    it "lists messages when generation is on Cursor and transcribe is on Aliyun" do
      enable_ai_assistant_module!(customer)
      assign_mixed_ai_assistant_vendors!

      bearer_get(desktop_access_token_for(admin))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("messages" => [], "pending_reply" => false)
    end

    it "returns an empty conversation for a desktop admin token" do
      enable_ai_assistant!(customer)
      bearer_get(desktop_access_token_for(admin))
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("messages" => [], "pending_reply" => false)
    end

    it "returns an unanswered user message without claiming a reply is pending" do
      enable_ai_assistant!(customer)
      conversation = create(:ai_assistant_conversation, customer: customer, user: admin)
      create(:ai_assistant_message, customer: customer, conversation: conversation, body: "Hello")

      bearer_get(desktop_access_token_for(admin))
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["pending_reply"]).to eq(false)
      expect(body["messages"].size).to eq(1)
      expect(body["messages"].first["role"]).to eq("user")
      expect(body["messages"].first["body"]).to eq("Hello")
      expect(body["messages"].first["status"]).to eq("complete")
      expect(body["messages"].first["created_at"]).to be_present
    end

    it "reports pending only while the conversation has a live generation" do
      enable_ai_assistant!(customer)
      conversation = create(:ai_assistant_conversation, customer: customer, user: admin)
      message = create(:ai_assistant_message, customer: customer, conversation: conversation, body: "Hello")
      generation = AiAssistant::Assistant::GenerationLifecycle.start!(conversation: conversation, user_message: message)
      token = desktop_access_token_for(admin)

      bearer_get(token)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["pending_reply"]).to eq(true)

      AiAssistant::Assistant::GenerationLifecycle.finish!(generation, status: :failed, failure_code: "enqueue_failed")
      bearer_get(token)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["pending_reply"]).to eq(false)
    end

    it "allows the platform owner to read another tenant's own thread" do
      enable_ai_assistant!(customer)
      owner = find_or_create_platform_owner
      conversation = create(:ai_assistant_conversation, customer: customer, user: owner)
      create(:ai_assistant_message, customer: customer, conversation: conversation, body: "Owner hi")

      bearer_get(desktop_access_token_for(owner))
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["messages"].map { |row| row["body"] }).to eq([ "Owner hi" ])
    end

    it "does not redirect an MFA-required user to the MFA page" do
      enable_ai_assistant!(customer)
      mfa_admin = create(:user, :admin, :with_mfa, customer: customer)
      bearer_get(desktop_access_token_for(mfa_admin))
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /:cid/admin/assistant/messages" do
    before do
      enable_ai_assistant!(customer)
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    end

    it "returns 202 and creates a user message" do
      bearer_post(desktop_access_token_for(admin), body: "Hello assistant")
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["message_id"]).to be_present
      expect(AiAssistant::Message.where(role: "user", body: "Hello assistant", customer: customer)).to exist
    end

    it "returns 422 for a blank body" do
      bearer_post(desktop_access_token_for(admin), body: " ")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(AiAssistant::Message.count).to eq(0)
    end

    it "rejects a cookie session" do
      sign_in admin
      post path, params: { body: "nope" }.to_json, headers: json_headers
      expect(response).to have_http_status(:unauthorized)
    end

    it "forbids an admin from another tenant posting to this tenant's cid" do
      stranger = create(:user, :admin, customer: create(:customer))
      bearer_post(desktop_access_token_for(stranger), body: "Hello")
      expect(response).to have_http_status(:forbidden)
      expect(AiAssistant::Message.count).to eq(0)
    end

    # Two admins in the same tenant each get their own thread; neither can see
    # or append to the other's.
    it "writes into the token owner's own conversation, never another user's" do
      other = create(:user, :admin, customer: customer)
      other_convo = create(:ai_assistant_conversation, customer: customer, user: other)

      bearer_post(desktop_access_token_for(admin), body: "Mine")

      expect(response).to have_http_status(:accepted)
      expect(other_convo.messages.reload).to be_empty
      expect(AiAssistant::Conversation.find_by(customer: customer, user: admin).messages.pluck(:body))
        .to eq([ "Mine" ])
    end

    it "does not expose another user's thread on read" do
      other = create(:user, :admin, customer: customer)
      other_convo = create(:ai_assistant_conversation, customer: customer, user: other)
      create(:ai_assistant_message, customer: customer, conversation: other_convo, body: "Secret")

      bearer_get(desktop_access_token_for(admin))
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["messages"]).to eq([])
    end

    it "returns 403 unconfigured when only a transcribe assignee is configured" do
      AiAssistant::ProviderSettings.update_all(generation_active: false)

      bearer_post(desktop_access_token_for(admin), body: "Hello assistant")

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["errors"]).to include(I18n.t("ai_assistant.errors.unconfigured"))
      expect(AiAssistant::Message.count).to eq(0)
    end

    it "accepts a message when generation is on Cursor and transcribe is on Aliyun" do
      AiAssistant::ProviderSettings.delete_all
      assign_mixed_ai_assistant_vendors!

      bearer_post(desktop_access_token_for(admin), body: "Hello mixed")

      expect(response).to have_http_status(:accepted)
      expect(AiAssistant::Message.where(role: "user", body: "Hello mixed", customer: customer)).to exist
    end
  end
end
