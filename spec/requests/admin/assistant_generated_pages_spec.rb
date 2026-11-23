# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Assistant-generated form access", type: :request do
  let(:customer) { ensure_platform_customer }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:member) { create(:user, :member, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: admin) }
  let!(:domain) { create(:entity_domain, customer: customer, name: "Academics") }
  let(:page) { Page.find_by!(customer_id: customer.id, name: "Generated Student") }
  let(:render_path) { admin_maintenance_page_render_path(customer.id, page) }
  let(:member_path) { "/#{customer.id}/member/pages/#{page.id}" }
  let(:public_path) { "/#{customer.id}/page/#{page.public_uuid}" }

  before do
    enable_ai_assistant!(customer)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
    texts = [
      {
        "tool" => "create_entity",
        "arguments" => { "domain" => domain.name, "entities" => [{
          "name" => "Generated Student", "attributes" => [{ "name" => "Full Name" }]
        }] }
      }.to_json,
      { "intent" => "chat", "reply" => "Created the form." }.to_json
    ]
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do
      { outcome: :success, text: texts.shift, raw: {} }
    end
    message = create(:ai_assistant_message, customer: customer, conversation: conversation,
                     role: "user", body: "Create a student form.")
    generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation, user_message: message
    )
    AiAssistant::ReplyJob.perform_now(generation.id)
    expect(generation.reload.status).to eq("completed")
  end

  it "renders the generated form for the tenant admin and denies member/public renders even to that admin" do
    sign_in admin
    get "/81721200/admin/assistant", params: { conversation: conversation.id }
    expect(response).to have_http_status(:ok)
    expect(page).to have_attributes(launched: true)
    expect(page.visible_audiences).to eq(%w[admin])

    get render_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Full Name", "Generated Student")

    get member_path
    expect(response).to have_http_status(:not_found)
    get public_path
    expect(response).to have_http_status(:not_found)
  end

  it "denies a member the generated form through every audience URL" do
    sign_in member

    get member_path
    expect(response).to have_http_status(:not_found)
    get public_path
    expect(response).to have_http_status(:not_found)
    get render_path
    expect(response).to redirect_to("/auth/sign_in")
  end

  it "does not expose the launched form anonymously" do
    get public_path
    expect(response).to have_http_status(:not_found)
    get render_path
    expect(response).to redirect_to("/auth/sign_in")
  end

  it "denies an unrelated tenant admin on both tenant paths" do
    other = create(:customer)
    sign_in create(:user, :admin, customer: other)

    get render_path
    expect(response).to redirect_to("/#{other.id}/admin/assistant")
    get admin_maintenance_page_render_path(other.id, page)
    expect(response).to have_http_status(:not_found)
  end
end
