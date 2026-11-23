# frozen_string_literal: true

require "ruby_llm"

# Llm
#
# Single app-level entry point for chat/completions, backed by the ruby_llm
# gem (per AGENTS.md: prefer a mature library, wrap it behind one thin
# service). Whisper transcription stays on ruby-openai; Cursor Cloud Agents
# stay on OutboundHttp.
#
# Callers never construct RubyLLM::Chat. Credentials are per-call via
# RubyLLM.context (platform encrypted keys or flowchart ENV keys).
class Llm
  DEFAULT_TIMEOUT = 60
  MAX_TOOL_CALLS = 8
  MAX_COMPLETIONS = MAX_TOOL_CALLS + 1
  OLLAMA_API_BASE = "http://localhost:11434/v1"
  QWEN_API_BASE = "https://dashscope.aliyuncs.com/compatible-mode/v1"
  PROVIDERS = %i[openai anthropic ollama bedrock deepseek qwen].freeze
  VISION_PROVIDERS = %i[openai anthropic ollama bedrock qwen].freeze

  class ToolLimitExceeded < StandardError; end
  class CallBudgetExceeded < StandardError; end

  # RubyLLM 1.16's before_message callback is AFTER the HTTP call for
  # non-streaming completions and also fires for tool-result messages. Its
  # provider_completion seam is the actual request boundary, including native
  # tool recursion. Prepend on this chat instance only, never globally.
  module CompletionBoundary
    private

    def provider_completion(&block)
      @anysys_before_request.call
      super(&block)
    end
  end

  CONFIGURATION_ERRORS = [
    RubyLLM::BadRequestError,
    RubyLLM::UnauthorizedError,
    RubyLLM::PaymentRequiredError,
    RubyLLM::ForbiddenError,
    RubyLLM::ContextLengthExceededError,
    RubyLLM::ConfigurationError,
    RubyLLM::ModelNotFoundError,
    RubyLLM::InvalidRoleError
  ].freeze

  def self.complete(**kwargs)
    new(**kwargs).complete
  end

  # @param on_chunk [#call, nil] receives each token as it arrives. Supplying
  #   it switches the request to server-sent streaming; the return value is
  #   unchanged either way, so a caller that cannot use partial text simply
  #   omits it.
  def initialize(provider:, model:, messages:, api_key:, organization: nil, json: false,
                 tools: nil, temperature: nil, max_tokens: nil, request_timeout: DEFAULT_TIMEOUT,
                 access_key_id: nil, region: nil, on_chunk: nil,
                 before_request: nil, before_tool_call: nil, call_budget: MAX_COMPLETIONS)
    @provider = provider.to_sym
    @model = model
    @messages = Array(messages)
    @api_key = api_key.to_s
    @organization = organization
    @json = json
    @tools = Array(tools).compact
    @temperature = temperature
    @max_tokens = max_tokens
    @request_timeout = request_timeout
    @access_key_id = access_key_id.to_s
    @region = region.to_s
    @on_chunk = on_chunk
    @before_request = before_request
    @before_tool_call = before_tool_call
    @call_budget = call_budget
    @calls = 0
  end

  def complete
    return failure(:configuration_error, "unsupported provider") unless PROVIDERS.include?(@provider)
    return failure(:configuration_error, "missing api_key") if @api_key.blank? && @provider != :ollama
    return failure(:configuration_error, "missing access_key_id") if @provider == :bedrock && @access_key_id.blank?
    return failure(:configuration_error, "missing region") if @provider == :bedrock && @region.blank?

    message = run_chat
    text = extract_text(message)
    if text.blank?
      { outcome: :empty, text: nil, raw: raw_of(message) }
    else
      { outcome: :success, text: text, raw: raw_of(message) }
    end
  rescue *CONFIGURATION_ERRORS, RubyLLM::UnsupportedAttachmentError => e
    failure(:configuration_error, e.message)
  rescue ToolLimitExceeded => e
    failure(:unreachable, e.message)
  rescue CallBudgetExceeded => e
    failure(:budget_exceeded, e.message)
  rescue RubyLLM::Error, Faraday::Error => e
    failure(:unreachable, e.message)
  end

  private

  def run_chat
    ctx = RubyLLM.context { |config| apply_provider_config(config) }
    chat = ctx.chat(model: @model, provider: ruby_llm_provider, assume_model_exists: true)
    seed(chat)
    apply_options(chat)
    chat.instance_variable_set(:@anysys_before_request, method(:reserve_request!))
    chat.singleton_class.prepend(CompletionBoundary)
    cap_tool_calls(chat)
    return chat.complete unless @on_chunk

    chat.complete { |chunk| emit(chunk) }
  end

  # Tool-call and usage frames arrive on the same stream with no content, and a
  # subscriber that raises must not take the whole completion down with it.
  def emit(chunk)
    content = chunk.respond_to?(:content) ? chunk.content : chunk
    return if content.nil?

    text = content.to_s
    @on_chunk.call(text) unless text.empty?
  rescue StandardError => e
    Rails.logger.error("[llm] stream subscriber failed: #{e.class}: #{e.message}")
  end

  def apply_provider_config(config)
    config.request_timeout = @request_timeout
    case @provider
    when :openai
      config.openai_api_key = @api_key
      config.openai_organization_id = @organization if @organization.present?
    when :anthropic
      config.anthropic_api_key = @api_key
    when :ollama
      config.ollama_api_base = OLLAMA_API_BASE
      config.ollama_api_key = @api_key if @api_key.present?
    when :bedrock
      config.bedrock_api_key = @access_key_id
      config.bedrock_secret_key = @api_key
      config.bedrock_region = @region
    when :deepseek
      config.deepseek_api_key = @api_key
    when :qwen
      config.openai_api_key = @api_key
      config.openai_api_base = QWEN_API_BASE
    end
  end

  def ruby_llm_provider
    @provider == :qwen ? :openai : @provider
  end

  def seed(chat)
    system_parts = []
    @messages.each do |msg|
      role = (msg[:role] || msg["role"]).to_s
      content = message_content(msg)
      if role == "system"
        system_parts << content.to_s
      else
        chat.add_message(role: role.to_sym, content: content)
      end
    end
    chat.with_instructions(system_parts.join("\n\n")) if system_parts.any?
  end

  def message_content(msg)
    text = (msg[:content] || msg["content"]).to_s
    images = Array(msg[:images] || msg["images"]).compact
    return text unless images.any? && VISION_PROVIDERS.include?(@provider)

    RubyLLM::Content.new(text, images)
  end

  def apply_options(chat)
    params = {}
    params[:response_format] = { type: "json_object" } if @json && @tools.empty?
    params[:max_tokens] = @max_tokens if @max_tokens
    chat.with_params(**params) if params.any?
    chat.with_temperature(@temperature) unless @temperature.nil?
    chat.with_tools(*@tools) if @tools.any?
  end

  def cap_tool_calls(chat)
    return if @tools.empty?

    count = 0
    chat.before_tool_call do
      @before_tool_call&.call
      count += 1
      raise ToolLimitExceeded, "tool call cap #{MAX_TOOL_CALLS}" if count > MAX_TOOL_CALLS
    end
  end

  def reserve_request!
    raise CallBudgetExceeded, "vendor_call_budget" if @calls >= @call_budget

    @before_request&.call
    @calls += 1
  end

  def extract_text(message)
    return "" unless message

    content = message.respond_to?(:content) ? message.content : message
    case content
    when Hash then content.to_json
    else content.to_s.strip
    end
  end

  def raw_of(message)
    message.respond_to?(:raw) ? message.raw : nil
  end

  def failure(outcome, error)
    { outcome: outcome, text: nil, raw: { "error" => error } }
  end
end
