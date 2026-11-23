# frozen_string_literal: true

# WEBrick owns HTTP parsing; Rack handles multipart decoding. The official RubyLLM and
# ruby-openai clients talk to this loopback service over their normal transport.
#
# Chat completions follow ruby_llm 1.16's OpenAI serializer:
#   - assistant tool rounds use `choices[].message.tool_calls` (function name + JSON
#     `arguments` string), `content` null, `finish_reason` `tool_calls`
#   - the follow-up request carries `role: "tool"` + `tool_call_id` (and, for the
#     JSON Loop convention, a user message whose content is `{"tool_result":...}`)
#   - streaming uses `chat.completion.chunk` deltas; tool_calls include `index: 0`
#     so StreamAccumulator can stitch fragments the same way a live OpenAI stream does
require "bundler/setup"
require "webrick"
require "json"
require "rack"
require "stringio"
require "json_schemer"
require "digest"

module BrowserProviderFixture
  DUMMY_KEY = "e2e-local-dummy-key"
  TRANSCRIPT = "Browser microphone fixture transcript."

  class InvalidCompletion < StandardError; end

  def self.validate_completion!(document, schema:)
    errors = JSONSchemer.schema(schema).validate(JSON.parse(document.to_json)).to_a
    raise InvalidCompletion, errors.map { |error| JSONSchemer::Errors.pretty(error) }.join("; ") if errors.any?

    document
  end

  def self.user_texts(messages)
    messages.select { |row| row["role"] == "user" }.map { |row| row["content"].to_s }
  end

  def self.system_text(messages)
    messages.select { |row| %w[system developer].include?(row["role"]) }.map { |row| row["content"] }.join("\n")
  end

  def self.entity_name(messages)
    joined = user_texts(messages).join("\n")
    joined[/\bCreate an? (PwC\w+) entity/i, 1] || joined[/Add a notes field to (\w+)/i, 1]
  end

  def self.notes_follow_up?(messages)
    user_texts(messages).last.to_s.match?(/Add a notes field to/i)
  end

  def self.tool_result_turn?(messages)
    last = messages.last || {}
    return true if last["role"] == "tool"

    parsed = JSON.parse(last["content"].to_s)
    parsed.is_a?(Hash) && parsed.key?("tool_result")
  rescue JSON::ParserError, TypeError
    false
  end

  def self.create_arguments(name)
    {
      "domain" => "Academics",
      "entities" => [
        {
          "name" => name,
          "attributes" => [{ "name" => "Title", "html_type" => "text" }]
        }
      ]
    }
  end

  def self.update_arguments(name)
    {
      "updates" => [
        {
          "entity" => name,
          "changes" => [
            { "op" => "add_attribute", "attribute" => { "name" => "Notes", "html_type" => "textarea" } }
          ]
        }
      ]
    }
  end

  def self.completion(messages)
    # RubyLLM's OpenAI serializer uses developer by default for instructions.
    if system_text(messages).include?("apply_flowchart")
      return {
        kind: :content,
        contract: "flowchart",
        document: { intent: "chat", reply: "No flowchart changes requested.", updates_confirmed: false, flowchart: nil }
      }
    end

    name = entity_name(messages)
    unless name
      return {
        kind: :content,
        document: { intent: "chat", reply: "Local browser fixture received the message." }
      }
    end

    if tool_result_turn?(messages)
      reply = if notes_follow_up?(messages)
        "I can add Notes to #{name}. Proceed?"
      else
        "Creating #{name} with a Title field."
      end
      return { kind: :content, document: { intent: "chat", reply: reply } }
    end

    if notes_follow_up?(messages)
      return { kind: :tool_call, name: "update_entity", arguments: update_arguments(name) }
    end

    { kind: :tool_call, name: "create_entity", arguments: create_arguments(name) }
  end

  def self.tool_call_payload(id:, name:, arguments:)
    {
      id: id,
      type: "function",
      function: {
        name: name,
        arguments: JSON.generate(arguments)
      }
    }
  end

  def self.completion_envelope(id:, model:, message:, finish_reason:)
    {
      id: id,
      object: "chat.completion",
      created: 1,
      model: model,
      choices: [{ index: 0, message: message, finish_reason: finish_reason }],
      usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 }
    }
  end

  def self.stream_body(envelope:, first_delta:, finish_reason:)
    frames = [first_delta, {}].each_with_index.map do |delta, index|
      chunk = envelope.merge(
        object: "chat.completion.chunk",
        choices: [{ index: 0, delta: delta, finish_reason: index == 1 ? finish_reason : nil }]
      )
      "data: #{chunk.to_json}\n\n"
    end
    frames.join + "data: [DONE]\n\n"
  end

  def self.serialize_completion(result, schemas:, request_id:, model:, stream:)
    if result[:kind] == :tool_call
      arguments = validate_completion!(result[:arguments], schema: schemas.fetch(result[:name]))
      tool_call = tool_call_payload(id: "call_e2e_#{request_id}", name: result[:name], arguments: arguments)
      message = { role: "assistant", content: nil, tool_calls: [tool_call] }
      envelope = completion_envelope(id: "chatcmpl-e2e-#{request_id}", model: model, message: message, finish_reason: "tool_calls")
      return [envelope, stream_body(
        envelope: envelope,
        first_delta: { role: "assistant", tool_calls: [tool_call.merge(index: 0)] },
        finish_reason: "tool_calls"
      )] if stream

      return [envelope, nil]
    end

    document = result[:document]
    if result[:contract]
      validate_completion!(document, schema: schemas.fetch(result[:contract]))
    end
    text = document.to_json
    message = { role: "assistant", content: text }
    envelope = completion_envelope(id: "chatcmpl-e2e-#{request_id}", model: model, message: message, finish_reason: "stop")
    return [envelope, stream_body(
      envelope: envelope,
      first_delta: { role: "assistant", content: text },
      finish_reason: "stop"
    )] if stream

    [envelope, nil]
  end

  def self.server(port:, schemas:)
    requests = []
    server = WEBrick::HTTPServer.new(BindAddress: "127.0.0.1", Port: port, AccessLog: [],
      Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN), MaxClients: 8)
    server.mount_proc("/") do |request, response|
      response["Content-Type"] = "application/json"
      if request.request_method == "GET" && request.path == "/health"
        response.body = { provider: "local-e2e-webrick", requests: requests }.to_json
      elsif request.request_method != "POST" || request["authorization"] != "Bearer #{DUMMY_KEY}"
        response.status = 403
        response.body = { error: "local dummy credential required" }.to_json
      elsif request.body.to_s.bytesize > 26 * 1024 * 1024
        response.status = 413
        response.body = { error: "fixture request too large" }.to_json
      elsif request.path == "/v1/audio/transcriptions"
        if request["content-type"].to_s.start_with?("multipart/form-data")
          parts = Rack::Multipart.parse_multipart("REQUEST_METHOD" => "POST", "CONTENT_TYPE" => request["content-type"],
            "CONTENT_LENGTH" => request.body.bytesize.to_s, "rack.input" => StringIO.new(request.body))
          audio = parts&.dig("file", :tempfile)
        end
        if audio && audio.size.positive?
          requests << { path: request.path, audioBytes: audio.size, audioSha256: Digest::SHA256.file(audio.path).hexdigest }
          response.body = { text: TRANSCRIPT }.to_json
        else
          response.status = 422
          response.body = { error: "real multipart audio required" }.to_json
        end
        audio&.close!
      elsif request.path == "/v1/chat/completions"
        begin
          payload = JSON.parse(request.body)
          messages = payload.fetch("messages", [])
          result = completion(messages)
          envelope, stream = serialize_completion(
            result,
            schemas: schemas,
            request_id: requests.length + 1,
            model: payload["model"],
            stream: !!payload["stream"]
          )
          requests << { path: request.path, stream: !!payload["stream"] }
          if stream
            response["Content-Type"] = "text/event-stream"
            response["Cache-Control"] = "no-cache"
            response.body = stream
          else
            response.body = envelope.to_json
          end
        rescue JSON::ParserError
          response.status = 400
          response.body = { error: "invalid JSON" }.to_json
        rescue InvalidCompletion => error
          response.status = 422
          response.body = { error: "invalid fixture completion", details: error.message }.to_json
        end
      else
        response.status = 404
        response.body = { error: "unknown fixture endpoint" }.to_json
      end
    end
    server
  end
end

if $PROGRAM_NAME == __FILE__
  schemas = JSON.parse($stdin.read)
  server = BrowserProviderFixture.server(port: Integer(ENV.fetch("E2E_PROVIDER_PORT", "3012")), schemas: schemas)
  %w[INT TERM].each { |signal| Signal.trap(signal) { server.shutdown } }
  $stdout.sync = true
  puts({ url: "http://127.0.0.1:#{server.config[:Port]}" }.to_json)
  server.start
end
