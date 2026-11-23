# frozen_string_literal: true

require "climate_control"

# Shared AI Assistant spec setup. Replaces the copy-pasted module enablement,
# mixed-vendor seeding, and E2E ENV stub that was inlined across request,
# activity, and provider specs.
module AiAssistantSpecHelpers
  def find_or_create_ai_assistant_module!
    find_or_create_feature_module!("ai_assistant", name: "AI Assistant")
  end

  def enable_ai_assistant_module!(for_customer)
    enable_module!("ai_assistant", for_customer, name: "AI Assistant")
  end

  def enable_ai_assistant!(for_customer, **settings_attrs)
    enable_ai_assistant_module!(for_customer)
    create(:ai_assistant_provider_settings, { generation_active: true }.merge(settings_attrs))
  end

  # The thread a send or a page load would open: the user's most recently
  # active unarchived one, created on demand. Replaces the removed
  # AiAssistant::Conversation.for_user in specs.
  def current_ai_assistant_conversation(for_customer, for_user)
    AiAssistant::Conversation.current_for(customer: for_customer, user: for_user)
  end

  def assign_mixed_ai_assistant_vendors!
    create(:ai_assistant_provider_settings,
           provider: "aliyun",
           api_key: "AKS",
           transcribe_active: true,
           generation_active: false,
           config: { access_key_id: "AKID", app_key: "app-1" }.to_json)
    create(:ai_assistant_provider_settings,
           provider: "cursor",
           api_key: "cur-test",
           transcribe_active: false,
           generation_active: true,
           config: { chat_model: "gpt-5" }.to_json)
  end

  def with_e2e_assistant_stub
    with_rails_env("development") do
      ClimateControl.modify(E2E_STUB_ASSISTANT: "1") { yield }
    end
  end
end

RSpec.configure do |config|
  config.include AiAssistantSpecHelpers
end
