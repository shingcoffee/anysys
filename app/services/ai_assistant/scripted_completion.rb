# frozen_string_literal: true

module AiAssistant
  # Development-only chat stand-in for Playwright. Enabled when
  # E2E_STUB_ASSISTANT=1; OpenaiWhisper delegates here so the vendor file
  # does not contain fixture conversation logic.
  class ScriptedCompletion
    def self.enabled?
      Rails.env.development? && ENV["E2E_STUB_ASSISTANT"].to_s == "1"
    end

    def self.call(messages:)
      new(messages).call
    end

    def initialize(messages)
      @messages = Array(messages)
    end

    def call
      { outcome: :success, text: document.to_json, raw: { "stub" => true } }
    end

    private

    def document
      return flowchart_document if flowchart_turn?
      return envelope if tool_result_last?

      if last_user.match?(/add .+\bto\b/i)
        update_tool
      else
        create_tool
      end
    end

    def flowchart_turn?
      system_text.include?("apply_flowchart")
    end

    def flowchart_document
      {
        "intent" => FlowchartDefinitions::Assistant::Extraction::Intent::CHAT,
        "reply" => "",
        "updates_confirmed" => false,
        "flowchart" => nil
      }
    end

    def system_text
      msg = @messages.find { |row| (row[:role] || row["role"]).to_s == "system" }
      return "" unless msg

      (msg[:content] || msg["content"]).to_s
    end

    def tool_result_last?
      parsed_last.is_a?(Hash) && parsed_last.key?("tool_result")
    end

    def parsed_last
      return @parsed_last if defined?(@parsed_last)

      last = @messages.last
      @parsed_last = if last
        JSON.parse((last[:content] || last["content"]).to_s)
      end
    rescue JSON::ParserError, TypeError
      @parsed_last = nil
    end

    def create_tool
      {
        "tool" => "create_entity",
        "arguments" => {
          "domain" => "Academics",
          "entities" => [
            {
              "name" => entity_name,
              "attributes" => [{ "name" => "Title", "html_type" => "text" }]
            }
          ]
        }
      }
    end

    def update_tool
      {
        "tool" => "update_entity",
        "arguments" => {
          "updates" => [
            {
              "entity" => entity_name,
              "changes" => [
                {
                  "op" => "add_attribute",
                  "attribute" => { "name" => "Notes", "html_type" => "textarea" }
                }
              ]
            }
          ]
        }
      }
    end

    def envelope
      result = parsed_last["tool_result"]
      result = result.deep_stringify_keys if result.is_a?(Hash)
      {
        "intent" => "chat",
        "reply" => envelope_reply(result)
      }
    end

    def envelope_reply(result)
      return "Creating #{entity_name} with a Title field." unless result.is_a?(Hash)

      case result["status"]
      when "succeeded"
        "Created #{entity_name} with a Title field."
      when "confirmation_required"
        "I can add Notes to #{entity_name}. Review the proposed changes and apply them, or tell me what to adjust."
      else
        result["next_step"].presence || "Done."
      end
    end

    def last_user
      user_texts.last.to_s
    end

    def entity_name
      user_texts.join("\n").scan(/\bCreate an? ([A-Za-z][\w]*)\b/i).flatten.last.presence || "E2eEntity"
    end

    def user_texts
      @user_texts ||= @messages.filter_map do |msg|
        next unless (msg[:role] || msg["role"]).to_s == "user"

        (msg[:content] || msg["content"]).to_s
      end
    end
  end
end
