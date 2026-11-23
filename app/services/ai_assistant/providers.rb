# frozen_string_literal: true

module AiAssistant
  # Registry of AI Assistant providers. Each provider subclass calls
  # `register!` when loaded; the registry then exposes them by key. The default
  # provider (the one auto-created on first access of ProviderSettings) is
  # whichever provider declares `default!`.
  #
  # Usage:
  #   AiAssistant::Providers.for("openai_whisper")
  #   AiAssistant::Providers.keys
  #   AiAssistant::Providers.default_key
  module Providers
    extend PluginRegistry.build(label: "AI Assistant provider", dir: "app/services/ai_assistant/providers")
  end
end
