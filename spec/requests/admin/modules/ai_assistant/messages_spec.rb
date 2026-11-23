# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::AiAssistant::Messages", type: :request do
  include_context "admin records"

  def path(cid = customer.id)
    "/#{cid}/admin/modules/ai_assistant/messages"
  end

  describe "POST create — auth" do
    let(:guard_path) { path }

    it_behaves_like "an admin-guarded request", :post
  end

  describe "cross-tenant URL isolation" do
    let(:other_customer) { create(:customer) }

    before { sign_in admin }

    it "does not dispatch create for another tenant" do
      allow(AiAssistant::Activities::SendMessage).to receive(:call)

      post path(other_customer.id),
           params: { body: "hi" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
      expect(AiAssistant::Activities::SendMessage).not_to have_received(:call)
    end

    it "does not dispatch stop for another tenant" do
      allow(AiAssistant::Activities::CancelReply).to receive(:call)

      post "#{path(other_customer.id)}/stop", headers: json_headers

      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
      expect(AiAssistant::Activities::CancelReply).not_to have_received(:call)
    end

    it "does not dispatch regenerate for another tenant" do
      allow(AiAssistant::Activities::RegenerateLast).to receive(:call)

      post "#{path(other_customer.id)}/regenerate", headers: json_headers

      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
      expect(AiAssistant::Activities::RegenerateLast).not_to have_received(:call)
    end
  end

  describe "GET mentions" do
    let(:guard_path) { "#{path}/mentions" }

    it_behaves_like "an admin-guarded request", :get

    it "lists what this tenant owns and nothing from another tenant" do
      sign_in admin
      enable_ai_assistant!(customer)
      entity = create(:entity, customer: customer, name: "Invoice", display_label: "Invoices")
      create(:flowchart, customer: customer, name: "Issue invoice")
      create(:entity, customer: create(:customer), name: "Foreign")

      get "#{path}/mentions", headers: json_headers

      expect(response).to have_http_status(:ok)
      mentions = response.parsed_body.fetch("mentions")
      expect(mentions).to include("kind" => "entity", "name" => "Invoice", "label" => "Invoices")
      expect(mentions.map { |row| row["name"] }).not_to include("Foreign")
      expect(mentions.map { |row| row["kind"] }).not_to include("flowchart")
    end

    it "lists flowcharts for the platform owner" do
      sign_in find_or_create_platform_owner
      enable_ai_assistant!(customer)
      entity = create(:entity, customer: customer, name: "Invoice")
      create(:flowchart, customer: customer, name: "Issue invoice")

      get "#{path}/mentions", headers: json_headers

      expect(response).to have_http_status(:ok)
      mentions = response.parsed_body.fetch("mentions")
      expect(mentions).to include(
        "kind" => "flowchart",
        "name" => "Issue invoice",
        "label" => "Issue invoice"
      )
    end

    it "refuses when the module is disabled for the tenant" do
      sign_in admin

      get "#{path}/mentions", headers: json_headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.fetch("errors")).to be_present
    end

    it "does not list another tenant's artifacts from that tenant's URL" do
      sign_in admin
      other = create(:customer)
      enable_ai_assistant!(customer)

      get "#{path(other.id)}/mentions", headers: json_headers

      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
    end
  end

  # "New chat" is a conversations#create now; the reset collection route is gone.
  # Non-routability itself is asserted in the conversations routing spec.
  it "no longer serves the reset collection action" do
    sign_in admin

    delete "#{path}/reset", headers: json_headers

    expect(response).to have_http_status(:not_found)
  end

  describe "POST create — admin" do
    before do
      sign_in admin
      enable_ai_assistant!(customer)
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
    end

    it "returns 202 and creates a user message" do
      post path, params: { body: "Hello assistant" }.to_json, headers: json_headers
      expect(response).to have_http_status(:accepted)
      expect(AiAssistant::Message.where(role: "user", body: "Hello assistant")).to exist
    end

    it "returns 422 for a blank body" do
      post path, params: { body: " " }.to_json, headers: json_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "sends into the conversation named in the body" do
      target = create(:ai_assistant_conversation, customer: customer, user: admin)
      create(:ai_assistant_conversation, customer: customer, user: admin)

      post path,
           params: { body: "into the named one", conversation_id: target.id }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:accepted)
      expect(target.reload.messages.pluck(:body)).to eq([ "into the named one" ])
    end

    it "returns 404 when the named conversation belongs to another user" do
      other = create(:user, :admin, customer: customer)
      foreign = create(:ai_assistant_conversation, customer: customer, user: other)

      post path,
           params: { body: "hi", conversation_id: foreign.id }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.messages).to be_empty
    end

    it "returns 403 unconfigured when only a transcribe assignee is configured" do
      AiAssistant::ProviderSettings.update_all(generation_active: false)

      post path, params: { body: "Hello assistant" }.to_json, headers: json_headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["errors"]).to include(I18n.t("ai_assistant.errors.unconfigured"))
      expect(AiAssistant::Message.count).to eq(0)
    end

    it "accepts a message when generation is on Cursor and transcribe is on Aliyun" do
      AiAssistant::ProviderSettings.delete_all
      assign_mixed_ai_assistant_vendors!

      post path, params: { body: "Hello mixed" }.to_json, headers: json_headers

      expect(response).to have_http_status(:accepted)
      expect(AiAssistant::Message.where(role: "user", body: "Hello mixed")).to exist
    end

    it "stores a positive proposal_message_id as confirms_message_id" do
      conversation = create(:ai_assistant_conversation, customer: customer, user: admin)
      proposal = create(:ai_assistant_message, :assistant, conversation: conversation, customer: customer)

      post path,
           params: {
             body: "yes",
             conversation_id: conversation.id,
             proposal_message_id: proposal.id
           }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:accepted)
      user_message = conversation.messages.where(role: "user").last
      expect(user_message.metadata_json["confirms_message_id"]).to eq(proposal.id)
    end

    it "ignores a non-numeric proposal_message_id" do
      post path,
           params: { body: "yes", proposal_message_id: "not-an-id" }.to_json,
           headers: json_headers

      expect(response).to have_http_status(:accepted)
      message = AiAssistant::Message.where(role: "user", body: "yes").last
      expect(message.metadata_json).not_to have_key("confirms_message_id")
    end
  end

  describe "POST stop" do
    def stop_path(cid = customer.id)
      "#{path(cid)}/stop"
    end

    def start_generation(customer:, user:)
      conversation = create(:ai_assistant_conversation, customer: customer, user: user)
      user_message = create(:ai_assistant_message, customer: customer, conversation: conversation)
      AiAssistant::Assistant::GenerationLifecycle.start!(
        conversation: conversation,
        user_message: user_message
      )
    end

    let(:guard_path) { stop_path }

    it_behaves_like "an admin-guarded request", :post

    it "cancels the signed-in admin's in-flight generation" do
      sign_in admin
      enable_ai_assistant_module!(customer)
      generation = start_generation(customer: customer, user: admin)
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)

      post stop_path, headers: json_headers

      expect(response).to have_http_status(:accepted)
      expect(generation.reload.status).to eq("cancelled")
    end

    it "does not cancel another tenant's generation" do
      other = create(:customer)
      other_admin = create(:user, :admin, customer: other)
      foreign_generation = start_generation(customer: other, user: other_admin)
      sign_in admin
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)

      post stop_path, headers: json_headers

      expect(response).to have_http_status(:accepted)
      expect(foreign_generation.reload.status).to eq("queued")
    end
  end

  describe "POST regenerate" do
    def regenerate_path(cid = customer.id)
      "#{path(cid)}/regenerate"
    end

    let(:guard_path) { regenerate_path }

    it_behaves_like "an admin-guarded request", :post

    it "replies to the last user turn on the signed-in admin's thread" do
      sign_in admin
      enable_ai_assistant!(customer)
      conversation = create(:ai_assistant_conversation, customer: customer, user: admin)
      last = create(:ai_assistant_message, conversation: conversation, customer: customer, body: "again")
      seed_generation = conversation.generations.create!(
        customer: customer,
        user_message: last,
        token: SecureRandom.uuid,
        status: "completed"
      )
      if seed_generation.id + 1 == last.id
        conversation.generations.create!(
          customer: customer,
          user_message: last,
          token: SecureRandom.uuid,
          status: "completed"
        )
      end
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)

      expect {
        post regenerate_path, headers: json_headers
      }.to have_enqueued_job(AiAssistant::ReplyJob)
      generation = conversation.reload.current_generation
      expect(generation.id).not_to eq(last.id)
      expect(AiAssistant::ReplyJob).to have_been_enqueued.with(generation.id)
      expect(response).to have_http_status(:accepted)
    end

    it "returns 422 when the thread has no user turn" do
      sign_in admin
      enable_ai_assistant!(customer)
      post regenerate_path, headers: json_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST undo" do
    def undo_path(message, cid = customer.id)
      "#{path(cid)}/#{message.id}/undo"
    end

    let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }
    let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: admin) }
    let(:website) { create(:website, customer: customer) }
    let(:page) { create(:website_page, website: website, customer: customer, title: "Menu", slug: "menu", position: 1) }
    let(:reply) do
      create(:ai_assistant_message, :assistant, conversation: conversation, customer: customer, body: "Built.",
        metadata: { "changes" => [], Websites::Assistant::Undo::KEY => { "pages" => [ Websites::Assistant::Undo.entry(page) ] } })
    end
    let(:guard_path) { undo_path(reply) }

    it_behaves_like "an admin-guarded request", :post

    context "when signed in as the admin" do
      before do
        sign_in admin
        enable_ai_assistant!(customer)
        enable_module!("website", customer)
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      end

      it "undoes the reply and redraws it in place" do
        post undo_path(reply), headers: turbo_headers

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include(%(target="ai_assistant_message_#{reply.id}"))
        expect(response.body).to include(I18n.t("ai_assistant.assistant.website.undo.done"))
        expect(WebsitePage.exists?(page.id)).to be(false)
      end

      it "redraws the reply with the refusal, escaping the page title, when the page changed since" do
        reply
        title = %(Menu <img src=x onerror="alert(1)">)
        page.update!(title: title)

        post undo_path(reply), headers: turbo_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include(%(role="alert"))
        expect(response.body).to include(CGI.escapeHTML(I18n.t("ai_assistant.assistant.website.undo.errors.changed", title: title)))
        expect(response.body).not_to include("<img src=x")
        expect(WebsitePage.exists?(page.id)).to be(true)
      end

      it "returns 404 when the owner posts a platform reply's id under this tenant's URL" do
        owner = find_or_create_platform_owner
        platform = owner.customer
        site = Website.find_by(customer_id: platform.id) || create(:website, customer: platform)
        ours = create(:website_page, website: site, customer: platform, title: "Ours", slug: "ours-#{SecureRandom.hex(3)}", position: 9)
        platform_reply = create(:ai_assistant_message, :assistant, customer: platform, body: "Built.",
          conversation: create(:ai_assistant_conversation, customer: platform, user: owner),
          metadata: { "changes" => [], Websites::Assistant::Undo::KEY => { "pages" => [ Websites::Assistant::Undo.entry(ours) ] } })
        sign_in owner

        post undo_path(platform_reply), headers: turbo_headers

        expect(response).to have_http_status(:not_found)
        expect(WebsitePage.exists?(ours.id)).to be(true)
      end

      it "returns 404 for a reply in another admin's conversation" do
        other = create(:user, :admin, customer: customer)
        foreign = create(:ai_assistant_message, :assistant, customer: customer, body: "Built.",
          conversation: create(:ai_assistant_conversation, customer: customer, user: other),
          metadata: reply.metadata)

        post undo_path(foreign), headers: turbo_headers

        expect(response).to have_http_status(:not_found)
        expect(WebsitePage.exists?(page.id)).to be(true)
      end
    end

    it "does not dispatch undo for another tenant" do
      other_customer = create(:customer)
      sign_in admin
      allow(AiAssistant::Activities::UndoWebsiteReply).to receive(:call)

      post undo_path(reply, other_customer.id), headers: turbo_headers

      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found).or have_http_status(:found)
      expect(AiAssistant::Activities::UndoWebsiteReply).not_to have_received(:call)
    end
  end

  describe "POST discard_proposal" do
    def discard_path(message, cid = customer.id)
      "#{path(cid)}/#{message.id}/discard_proposal"
    end

    def park_invocation!(for_customer:, for_user:, for_conversation:)
      create(
        :operation_invocation,
        :awaiting_confirmation,
        customer: for_customer,
        user: for_user,
        operation: "update_entity",
        conversation_id: for_conversation.id
      )
    end

    def proposal_payload(invocation, for_customer:)
      {
        "kind" => "operation",
        "operation" => "update_entity",
        "invocation_id" => invocation.id,
        "customer_id" => for_customer.id,
        "plan" => [ {
          "name" => "Student",
          "breaking" => false,
          "rows" => [ {
            "kind" => "attribute",
            "action" => "added",
            "name" => "Notes",
            "html_type" => "textarea",
            "breaking" => false
          } ]
        } ]
      }
    end

    def park_proposal!(for_customer:, for_user:, for_conversation: nil, metadata_key: "pending_confirmation")
      conversation = for_conversation || create(
        :ai_assistant_conversation, customer: for_customer, user: for_user
      )
      invocation = park_invocation!(
        for_customer: for_customer, for_user: for_user, for_conversation: conversation
      )
      message = create(
        :ai_assistant_message,
        :assistant,
        conversation: conversation,
        customer: for_customer,
        metadata: { metadata_key => proposal_payload(invocation, for_customer: for_customer) }
      )
      [ message, invocation ]
    end

    let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }
    let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: admin) }
    let(:reply) do
      message, = park_proposal!(
        for_customer: customer, for_user: admin, for_conversation: conversation
      )
      message
    end
    let(:guard_path) { discard_path(reply) }

    it_behaves_like "an admin-guarded request", :post

    context "when signed in as the admin" do
      before do
        sign_in admin
        enable_ai_assistant!(customer)
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      end

      it "discards the pending proposal and redraws the declined panel" do
        message, invocation = park_proposal!(
          for_customer: customer, for_user: admin, for_conversation: conversation
        )

        post discard_path(message), headers: turbo_headers

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include(%(target="ai_assistant_message_#{message.id}"))
        expect(response.body).to include(I18n.t("ai_assistant.assistant.plan.declined"))
        metadata = message.reload.metadata_json
        expect(metadata).not_to have_key("pending_confirmation")
        expect(metadata["declined_proposal"]).to include(
          "kind" => "operation",
          "invocation_id" => invocation.id
        )
        expect(invocation.reload.status).to eq("declined")
      end

      it "returns 422 when the proposal is already settled" do
        message, invocation = park_proposal!(
          for_customer: customer,
          for_user: admin,
          for_conversation: conversation,
          metadata_key: "applied_proposal"
        )
        invocation.update!(status: "succeeded")

        post discard_path(message), headers: turbo_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(message.reload.metadata_json).to have_key("applied_proposal")
        expect(message.reload.metadata_json).not_to have_key("declined_proposal")
        expect(invocation.reload.status).to eq("succeeded")
      end

      it "returns 404 for a proposal in another admin's conversation" do
        other = create(:user, :admin, customer: customer)
        foreign, invocation = park_proposal!(for_customer: customer, for_user: other)

        post discard_path(foreign), headers: turbo_headers

        expect(response).to have_http_status(:not_found)
        expect(foreign.reload.metadata_json).to have_key("pending_confirmation")
        expect(invocation.reload.status).to eq("awaiting_confirmation")
      end

      it "returns 404 for another tenant's message id under this tenant's URL" do
        other_customer = create(:customer)
        other_admin = create(:user, :admin, customer: other_customer)
        foreign, invocation = park_proposal!(for_customer: other_customer, for_user: other_admin)

        post discard_path(foreign), headers: turbo_headers

        expect(response).to have_http_status(:not_found)
        expect(foreign.reload.metadata_json).to have_key("pending_confirmation")
        expect(invocation.reload.status).to eq("awaiting_confirmation")
      end
    end

    it "refuses when the module is disabled for the tenant" do
      sign_in admin
      message, invocation = park_proposal!(
        for_customer: customer, for_user: admin, for_conversation: conversation
      )

      post discard_path(message), headers: turbo_headers

      expect(response).to have_http_status(:forbidden)
      expect(message.reload.metadata_json).to have_key("pending_confirmation")
      expect(invocation.reload.status).to eq("awaiting_confirmation")
    end

    it "does not dispatch discard_proposal for another tenant" do
      other_customer = create(:customer)
      sign_in admin

      post discard_path(reply, other_customer.id), headers: turbo_headers

      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found).or have_http_status(:found)
      expect(reply.reload.metadata_json).to have_key("pending_confirmation")
    end
  end

  describe "POST cancel_build" do
    let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }
    let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: admin) }

    def cancel_path(message, cid = customer.id)
      "#{path(cid)}/#{message.id}/cancel_build"
    end

    def build_message!(for_customer: customer, for_conversation: conversation, status: "running")
      build = AiAssistant::SubsystemBuild.create!(customer_id: for_customer.id, conversation: for_conversation,
                                                  user: for_conversation.user, status: status, blueprint: { "domain" => "School" })
      message = create(:ai_assistant_message, :assistant, conversation: for_conversation, customer: for_customer,
                                                          metadata: { "subsystem_build" => { "id" => build.id } })
      [message, build]
    end

    let(:guard_path) { cancel_path(build_message!.first) }

    it_behaves_like "an admin-guarded request", :post

    context "when signed in as the admin" do
      before do
        sign_in admin
        enable_ai_assistant!(customer)
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      end

      it "cancels the build and redraws the message without the Cancel button" do
        message, build = build_message!

        post cancel_path(message), headers: turbo_headers

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include(%(target="ai_assistant_message_#{message.id}"))
        expect(response.body).to include(I18n.t("ai_assistant.subsystems.status.cancelled"))
        expect(response.body).not_to include(I18n.t("ai_assistant.subsystems.cancel.button"))
        expect(build.reload.status).to eq("cancelled")
      end

      it "returns 422 for a build that has already ended" do
        message, build = build_message!(status: "finished")

        post cancel_path(message), headers: turbo_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(build.reload.status).to eq("finished")
      end

      it "returns 404 for a build in another admin's conversation" do
        other = create(:ai_assistant_conversation, customer: customer, user: create(:user, :admin, customer: customer))
        message, build = build_message!(for_conversation: other)

        post cancel_path(message), headers: turbo_headers

        expect(response).to have_http_status(:not_found)
        expect(build.reload.status).to eq("running")
      end

      it "returns 404 for another tenant's message id under this tenant's URL" do
        other_customer = create(:customer)
        other = create(:ai_assistant_conversation, customer: other_customer, user: create(:user, :admin, customer: other_customer))
        message, build = build_message!(for_customer: other_customer, for_conversation: other)

        post cancel_path(message), headers: turbo_headers

        expect(response).to have_http_status(:not_found)
        expect(build.reload.status).to eq("running")
      end

      it "returns 404 for a message whose build belongs to another conversation" do
        _, build = build_message!(for_conversation: create(:ai_assistant_conversation, customer: customer, user: admin))
        message = create(:ai_assistant_message, :assistant, conversation: conversation, customer: customer,
                                                            metadata: { "subsystem_build" => { "id" => build.id } })

        post cancel_path(message), headers: turbo_headers

        expect(response).to have_http_status(:not_found)
        expect(build.reload.status).to eq("running")
      end
    end

    it "is forbidden to a member" do
      message, build = build_message!
      sign_in create(:user, :member, customer: customer)

      post cancel_path(message), headers: turbo_headers

      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
      expect(build.reload.status).to eq("running")
    end
  end
end
