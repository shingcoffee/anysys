# frozen_string_literal: true

module Captcha
  # Rebuilds a captured POST (including files) and internally dispatches it.
  class RequestReplayer
    def self.call(env:, payload:)
      new(env: env, payload: payload).call
    end

    def initialize(env:, payload:)
      @env = env
      @payload = payload
    end

    def call
      request = ActionDispatch::Request.new(@env)
      unless Captcha::SessionBinding.matches?(request.session, @payload["binding"]) &&
          request.base_url == @payload["origin"]
        raise ActionController::InvalidAuthenticityToken
      end
      body, content_type = encode_body
      replay_env = @env.dup
      replay_env["REQUEST_METHOD"] = @payload["method"].presence || "POST"
      replay_env["PATH_INFO"] = @payload["path_info"]
      replay_env["SCRIPT_NAME"] = @payload["script_name"]
      replay_env["QUERY_STRING"] = @payload["query"].to_s
      fullpath = @payload["path"] + (replay_env["QUERY_STRING"].present? ? "?#{replay_env['QUERY_STRING']}" : "")
      replay_env["REQUEST_URI"] = fullpath
      replay_env["ORIGINAL_FULLPATH"] = fullpath
      replay_env["CONTENT_TYPE"] = content_type
      replay_env["CONTENT_LENGTH"] = body.bytesize.to_s
      replay_env["rack.input"] = StringIO.new(body)
      replay_env["captcha.replay"] = true
      %w[HTTP_ORIGIN HTTP_REFERER HTTP_X_CSRF_TOKEN].each do |name|
        replay_env[name] = @payload.fetch("headers")[name]
      end
      replay_env.delete("action_controller.csrf_token")
      replay_env.delete("action_controller.instance")
      replay_env.delete("action_dispatch.request.content_type")
      replay_env.delete("action_dispatch.request.formats")
      replay_env.delete("action_dispatch.request.request_parameters")
      replay_env.delete("action_dispatch.request.query_parameters")
      replay_env.delete("action_dispatch.request.parameters")
      replay_env.delete("action_dispatch.request.path_parameters")
      replay_env.delete(PageShortcuts::Resolver::CACHE_KEY)
      replay_env.delete("page_shortcuts.route_match")
      replay_env.delete("rack.request.form_hash")
      replay_env.delete("rack.request.form_input")
      replay_env.delete("rack.request.form_vars")
      replay_env.delete("rack.request.form_pairs")
      replay_env.delete("rack.request.form_error")
      replay_env.delete("rack.request.query_hash")
      replay_env.delete("rack.request.query_string")

      Captcha::OriginalRequestVerifier.verify!(ActionDispatch::Request.new(replay_env))
      response = Rails.application.call(replay_env)
      # Session middleware builds a fresh session object for the nested dispatch.
      # Preserve target-side writes/reset_session when the outer challenge's
      # middleware commits, instead of restoring its pre-replay session/CSRF.
      %w[rack.session rack.session.options action_controller.csrf_token].each do |name|
        replay_env.key?(name) ? @env[name] = replay_env[name] : @env.delete(name)
      end
      response
    ensure
      purge_blobs
    end

    private

    def encode_body
      params = (@payload["params"] || {}).dup
      files = @payload["files"] || {}

      if files.blank?
        encoded = Rack::Utils.build_nested_query(params)
        return [encoded, "application/x-www-form-urlencoded"]
      end

      boundary = "----CaptchaReplay#{SecureRandom.hex(16)}"
      parts = []
      flatten_params(params).each do |name, value|
        parts << text_part(boundary, name, value)
      end
      files.each do |name, blobs|
        Array(blobs).each do |meta|
          blob = ActiveStorage::Blob.find_signed(meta["signed_id"])
          next unless blob

          parts << file_part(boundary, name, blob, meta)
        end
      end
      body = "#{parts.join}--#{boundary}--\r\n"
      [body, "multipart/form-data; boundary=#{boundary}"]
    end

    def flatten_params(value, prefix = nil)
      case value
      when Hash
        value.flat_map { |k, v| flatten_params(v, prefix ? "#{prefix}[#{k}]" : k.to_s) }
      when Array
        value.flat_map { |v| flatten_params(v, "#{prefix}[]") }
      else
        [[prefix, value]]
      end
    end

    def text_part(boundary, name, value)
      "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n"
    end

    def file_part(boundary, name, blob, meta)
      filename = meta["filename"].presence || blob.filename.to_s
      content_type = meta["content_type"].presence || blob.content_type
      data = blob.download
      header = "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"; filename=\"#{filename}\"\r\n" \
               "Content-Type: #{content_type}\r\n\r\n"
      "#{header}#{data}\r\n"
    end

    def purge_blobs
      (@payload["files"] || {}).each_value do |blobs|
        Array(blobs).each do |meta|
          ActiveStorage::Blob.find_signed(meta["signed_id"])&.purge
        rescue StandardError
          nil
        end
      end
    end
  end
end
