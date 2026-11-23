# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::AiAssistant::Conversations", type: :request do
  include_context "admin records"

  def path(cid = customer.id)
    "/#{cid}/admin/modules/ai_assistant/conversations"
  end

  let(:other_customer) { create(:customer) }

  describe "authorization" do
    describe "GET index" do
      let(:guard_path) { path }

      it_behaves_like "an admin-guarded GET"
    end

    describe "POST create" do
      let(:guard_path) { path }

      it_behaves_like "an admin-guarded request", :post
    end

    describe "PATCH update" do
      let(:guard_path) { "#{path}/1" }

      it_behaves_like "an admin-guarded request", :patch
    end

    describe "POST archive" do
      let(:guard_path) { "#{path}/1/archive" }

      it_behaves_like "an admin-guarded request", :post
    end

    describe "DELETE destroy" do
      let(:guard_path) { "#{path}/1" }

      it_behaves_like "an admin-guarded request", :delete
    end

    it "admits the platform owner" do
      owner = find_or_create_platform_owner
      enable_ai_assistant_module!(owner.customer)
      sign_in owner

      get path(owner.customer.id), headers: json_headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "cross-tenant URL isolation" do
    before { sign_in admin }

    it "refuses index on another tenant's URL" do
      allow(AiAssistant::Activities::ListConversations).to receive(:call)

      get path(other_customer.id), headers: json_headers

      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
      expect(AiAssistant::Activities::ListConversations).not_to have_received(:call)
    end

    it "refuses create on another tenant's URL" do
      allow(AiAssistant::Activities::StartConversation).to receive(:call)

      post path(other_customer.id), headers: json_headers

      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
      expect(AiAssistant::Activities::StartConversation).not_to have_received(:call)
    end

    it "refuses destroy on another tenant's URL" do
      other_admin = create(:user, :admin, customer: other_customer)
      foreign = create(:ai_assistant_conversation, customer: other_customer, user: other_admin)

      delete "#{path(other_customer.id)}/#{foreign.id}", headers: json_headers

      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
      expect(AiAssistant::Conversation.find_by(id: foreign.id)).to be_present
    end
  end

  describe "as the signed-in admin" do
    before do
      sign_in admin
      enable_ai_assistant_module!(customer)
      allow(AiAssistant::Stream).to receive(:broadcast_conversations)
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
    end

    describe "GET index" do
      it "returns the admin's own threads split by archived state" do
        open_thread = create(:ai_assistant_conversation, customer: customer, user: admin,
                                                         title: "Open one", last_active_at: 1.hour.ago)
        filed = create(:ai_assistant_conversation, :archived, customer: customer, user: admin,
                                                             title: "Filed one", last_active_at: 2.days.ago)

        get path, headers: json_headers

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body.fetch("active")).to eq([
          { "id" => open_thread.id, "title" => "Open one", "archived" => false,
            "last_active_at" => open_thread.last_active_at.iso8601, "current" => true }
        ])
        expect(body.fetch("archived")).to eq([
          { "id" => filed.id, "title" => "Filed one", "archived" => true,
            "last_active_at" => filed.last_active_at.iso8601, "current" => false }
        ])
      end

      it "falls back to the opening prompt for an unnamed thread" do
        thread = create(:ai_assistant_conversation, customer: customer, user: admin)
        create(:ai_assistant_message, conversation: thread, customer: customer, body: "Draft a policy")

        get path, headers: json_headers

        expect(response.parsed_body.dig("active", 0, "title")).to eq("Draft a policy")
      end

      it "labels a thread with neither title nor turns" do
        create(:ai_assistant_conversation, customer: customer, user: admin)

        get path, headers: json_headers

        expect(response.parsed_body.dig("active", 0, "title"))
          .to eq(I18n.t("ai_assistant.assistant.conversations.untitled"))
      end

      it "does not list another admin's threads in the same tenant" do
        other = create(:user, :admin, customer: customer)
        create(:ai_assistant_conversation, customer: customer, user: other, title: "Not mine")

        get path, headers: json_headers

        expect(response.body).not_to include("Not mine")
        expect(response.parsed_body.fetch("active")).to eq([])
      end

      it "returns 403 when the module is disabled for the tenant" do
        fm = FeatureModules::Module.find_by!(key: "ai_assistant")
        FeatureModules::CustomerAssignment.where(customer: customer, feature_module: fm).delete_all

        get path, headers: json_headers

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body.fetch("errors"))
          .to include(I18n.t("ai_assistant.errors.module_disabled"))
      end
    end

    describe "POST create" do
      it "starts a thread owned by the signed-in admin" do
        expect { post path, headers: json_headers }
          .to change(AiAssistant::Conversation, :count).by(1)

        expect(response).to have_http_status(:created)
        created = AiAssistant::Conversation.last
        expect(created).to have_attributes(customer_id: customer.id, user_id: admin.id)
        expect(response.parsed_body.dig("conversation", "id")).to eq(created.id)
        expect(response.parsed_body.dig("conversation", "current")).to be(true)
      end

      it "returns 422 when the admin's open thread has not been used yet" do
        create(:ai_assistant_conversation, customer: customer, user: admin)

        expect { post path, headers: json_headers }
          .not_to change(AiAssistant::Conversation, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.fetch("errors"))
          .to include(I18n.t("ai_assistant.errors.current_chat_empty"))
      end

      it "returns 429 at the per-user ceiling" do
        AiAssistant::Conversation::MAX_PER_USER.times do
          create(:ai_assistant_conversation, customer: customer, user: admin)
        end

        post path, headers: json_headers

        expect(response).to have_http_status(:too_many_requests)
        expect(response.parsed_body.fetch("errors")).to include(
          I18n.t("ai_assistant.errors.conversation_count_limit",
                 count: AiAssistant::Conversation::MAX_PER_USER)
        )
      end
    end

    describe "PATCH update" do
      let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: admin) }

      it "renames the admin's own thread" do
        patch "#{path}/#{conversation.id}",
              params: { title: "Renamed" }.to_json, headers: json_headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("conversation", "title")).to eq("Renamed")
        expect(conversation.reload.title).to eq("Renamed")
      end

      it "returns 422 for a blank title" do
        patch "#{path}/#{conversation.id}",
              params: { title: " " }.to_json, headers: json_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body.fetch("errors").join)
          .to include(I18n.t("ai_assistant.errors.title_blank"))
        expect(conversation.reload.title).to be_nil
      end

      it "returns 404 for another admin's thread in the same tenant" do
        other = create(:user, :admin, customer: customer)
        foreign = create(:ai_assistant_conversation, customer: customer, user: other, title: "Theirs")

        patch "#{path}/#{foreign.id}",
              params: { title: "Mine now" }.to_json, headers: json_headers

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body.fetch("errors"))
          .to include(I18n.t("ai_assistant.errors.conversation_not_found"))
        expect(foreign.reload.title).to eq("Theirs")
      end

      it "returns 404 for a thread in another tenant" do
        other_admin = create(:user, :admin, customer: other_customer)
        foreign = create(:ai_assistant_conversation, customer: other_customer, user: other_admin,
                                                        title: "Theirs")

        patch "#{path}/#{foreign.id}",
              params: { title: "Mine now" }.to_json, headers: json_headers

        expect(response).to have_http_status(:not_found)
        expect(foreign.reload.title).to eq("Theirs")
      end
    end

    describe "POST archive" do
      let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: admin) }

      it "archives by default" do
        post "#{path}/#{conversation.id}/archive", headers: json_headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("conversation", "archived")).to be(true)
        expect(conversation.reload).to be_archived
      end

      it "unarchives when told to" do
        filed = create(:ai_assistant_conversation, :archived, customer: customer, user: admin)

        post "#{path}/#{filed.id}/archive",
             params: { archived: false }.to_json, headers: json_headers

        expect(response).to have_http_status(:ok)
        expect(filed.reload).not_to be_archived
      end

      it "returns 404 for another admin's thread" do
        other = create(:user, :admin, customer: customer)
        foreign = create(:ai_assistant_conversation, customer: customer, user: other)

        post "#{path}/#{foreign.id}/archive", headers: json_headers

        expect(response).to have_http_status(:not_found)
        expect(foreign.reload).not_to be_archived
      end
    end

    describe "DELETE destroy" do
      it "deletes the admin's own thread" do
        conversation = create(:ai_assistant_conversation, customer: customer, user: admin)
        create(:ai_assistant_message, conversation: conversation, customer: customer)

        delete "#{path}/#{conversation.id}", headers: json_headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.fetch("conversation_id")).to eq(conversation.id)
        expect(AiAssistant::Conversation.find_by(id: conversation.id)).to be_nil
      end

      it "returns 404 for another admin's thread in the same tenant" do
        other = create(:user, :admin, customer: customer)
        foreign = create(:ai_assistant_conversation, customer: customer, user: other)

        delete "#{path}/#{foreign.id}", headers: json_headers

        expect(response).to have_http_status(:not_found)
        expect(AiAssistant::Conversation.find_by(id: foreign.id)).to be_present
      end

      it "returns 404 for an id that does not exist" do
        delete "#{path}/999999", headers: json_headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
