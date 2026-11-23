# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Assistants#show", type: :request do
  include_context "as admin"
  let(:guard_path) { "/#{customer.id}/admin/assistant" }

  it_behaves_like "an admin-guarded GET"

  def enable_assistant!
    enable_ai_assistant!(customer)
  end

  it "renders the assistant when the module is enabled and a provider is configured" do
    enable_assistant!

    get "/#{customer.id}/admin/assistant"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("ai_assistant.assistant.title"))
    expect(response.body).not_to include(I18n.t("ai_assistant.assistant.what"))
    expect(response.body).to include(I18n.t("ai_assistant.assistant.how"))
    expect(response.body).to include(I18n.t("ai_assistant.assistant.placeholder"))
    expect(response.body).to include("data-controller=\"ai-assistant\"")
    expect(response.body).to include(%(id="ai_assistant_composer"))
    expect(response.body).not_to include(I18n.t("admin_misc.dashboard.quick_actions"))
  end

  it "renders prior assistant messages on the assistant page" do
    enable_assistant!
    conversation = create(:ai_assistant_conversation, customer: customer, user: admin)
    create(:ai_assistant_message, conversation: conversation, customer: customer, body: "Prior assistant turn")

    get "/#{customer.id}/admin/assistant"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Prior assistant turn")
    expect(response.body).not_to include(I18n.t("ai_assistant.assistant.what"))
    expect(response.body).not_to include(I18n.t("ai_assistant.assistant.try"))
    expect(response.body).not_to include(%(id="ai_assistant_empty"))
  end

  it "hides the attach control when DeepSeek is the generation vendor" do
    enable_ai_assistant!(
      customer,
      provider: "deepseek",
      api_key: "sk-deep",
      transcribe_active: false,
      generation_active: true
    )

    get "/#{customer.id}/admin/assistant"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("ai_assistant.assistant.placeholder"))
    expect(response.body).not_to include(I18n.t("ai_assistant.assistant.attach"))
    expect(response.body).not_to include("data-ai-assistant-target=\"images\"")
  end

  it "renders the offline empty state when the module is not enabled" do
    get "/#{customer.id}/admin/assistant"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(I18n.t("ai_assistant.assistant.placeholder"))
    expect(response.body).to include(I18n.t("ai_assistant.assistant.offline.body"))
    expect(response.body).to include(I18n.t("ai_assistant.assistant.offline.cta"))
  end

  it "renders the offline empty state when only a transcribe assignee is configured" do
    enable_ai_assistant_module!(customer)
    create(:ai_assistant_provider_settings, transcribe_active: true, generation_active: false)

    get "/#{customer.id}/admin/assistant"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(I18n.t("ai_assistant.assistant.placeholder"))
    expect(response.body).to include(I18n.t("ai_assistant.assistant.offline.body"))
  end

  it "highlights the AI Assistant menu item" do
    get "/#{customer.id}/admin/assistant"

    html = Nokogiri::HTML(response.body)
    current = html.at("a[aria-current='page']")
    expect(current.text).to include(I18n.t("chrome.menu_bar.items.assistant"))
    expect(current["href"]).to eq(admin_assistant_path(customer.id))
  end

  it "serves the AI Assistant at the admin namespace root" do
    get "/#{customer.id}/admin"

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    current = html.at("a[aria-current='page']")
    expect(current.text).to include(I18n.t("chrome.menu_bar.items.assistant"))
  end

  it "rejects a same-role admin using another tenant's URL" do
    other_customer = create(:customer)

    get "/#{other_customer.id}/admin/assistant"

    # Tenant denials now resolve the destination through
    # Authentication::LandingPath rather than hard-coding a path, so the
    # target follows the actor's role instead of assuming admin.
    expect(response).to redirect_to("/#{customer.id}/admin/assistant")
    expect(response).not_to have_http_status(:ok)
  end

  it "does not show another tenant's conversation" do
    enable_assistant!
    other = create(:customer)
    other_admin = create(:user, :admin, customer: other)
    conversation = create(:ai_assistant_conversation, customer: other, user: other_admin)
    create(:ai_assistant_message, conversation: conversation, customer: other, body: "Secret other tenant")

    get "/#{customer.id}/admin/assistant"

    expect(response.body).not_to include("Secret other tenant")
  end

  # The thread to open travels as `?conversation=<id>` rather than a path
  # segment: /:cid/admin/assistant/... is already the desktop Bearer API.
  describe "?conversation=" do
    it "opens the requested thread instead of the most recently active one" do
      enable_assistant!
      create(:ai_assistant_conversation, customer: customer, user: admin, last_active_at: 1.hour.ago)
      older = create(:ai_assistant_conversation, customer: customer, user: admin,
                                                 last_active_at: 3.days.ago)
      create(:ai_assistant_message, conversation: older, customer: customer, body: "In the old thread")

      get "/#{customer.id}/admin/assistant", params: { conversation: older.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("In the old thread")
    end

    it "opens the most recently active thread when no id is given" do
      enable_assistant!
      create(:ai_assistant_conversation, customer: customer, user: admin, last_active_at: 3.days.ago)
      newest = create(:ai_assistant_conversation, customer: customer, user: admin,
                                                  last_active_at: 1.minute.ago)
      create(:ai_assistant_message, conversation: newest, customer: customer, body: "In the new thread")

      get "/#{customer.id}/admin/assistant"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("In the new thread")
    end

    it "opens an archived thread the admin asks for by id" do
      enable_assistant!
      filed = create(:ai_assistant_conversation, :archived, customer: customer, user: admin)
      create(:ai_assistant_message, conversation: filed, customer: customer, body: "Filed away")

      get "/#{customer.id}/admin/assistant", params: { conversation: filed.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Filed away")
    end

    it "redirects to the canonical path for another admin's thread" do
      enable_assistant!
      other = create(:user, :admin, customer: customer)
      foreign = create(:ai_assistant_conversation, customer: customer, user: other)
      create(:ai_assistant_message, conversation: foreign, customer: customer, body: "Not yours")

      get "/#{customer.id}/admin/assistant", params: { conversation: foreign.id }

      expect(response).to redirect_to(admin_assistant_path(customer.id))
      expect(flash[:alert]).to eq(I18n.t("ai_assistant.errors.conversation_not_found"))
    end

    it "redirects to the canonical path for a thread in another tenant" do
      enable_assistant!
      other_customer = create(:customer)
      other_admin = create(:user, :admin, customer: other_customer)
      foreign = create(:ai_assistant_conversation, customer: other_customer, user: other_admin)

      get "/#{customer.id}/admin/assistant", params: { conversation: foreign.id }

      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end

    it "redirects to the canonical path for an id that does not exist" do
      enable_assistant!

      get "/#{customer.id}/admin/assistant", params: { conversation: 999_999 }

      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end
  end

  it "renders page artifact destinations under the current tenant" do
    enable_assistant!
    conversation = create(:ai_assistant_conversation, customer: customer, user: admin)
    page_record = create(:page, customer: customer, name: "Current tenant page")
    AiAssistant::Assistant::Artifact.assign_record!(conversation, record: page_record)

    get "/#{customer.id}/admin/assistant"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin_maintenance_page_preview_path(customer.id, page_record))
    expect(response.body).to include(admin_maintenance_page_path(customer.id, page_record))
  end

  it "does not render destinations for a page artifact outside the current tenant" do
    enable_assistant!
    conversation = create(:ai_assistant_conversation, customer: customer, user: admin)
    other_customer = create(:customer)
    other_page = create(:page, customer: other_customer, name: "Foreign tenant page")
    conversation.update!(artifact_kind: "page", artifact_id: other_page.id)

    get "/#{customer.id}/admin/assistant"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Foreign tenant page")
    expect(response.body).not_to include(admin_maintenance_page_preview_path(customer.id, other_page))
    expect(response.body).not_to include(admin_maintenance_page_path(customer.id, other_page))
  end
end
