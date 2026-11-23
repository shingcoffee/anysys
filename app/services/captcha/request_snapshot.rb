# frozen_string_literal: true

module Captcha
  # One-time POST snapshot (params + uploaded files) so a captcha pass can
  # replay the original request. The consume token is an HttpOnly cookie, not
  # a query string. Metadata lives in the throttle cache; files are Active
  # Storage blobs under captcha/snapshots/.
  class RequestSnapshot
    PREFIX = "captcha:snapshot"
    COOKIE = "captcha_snapshot"
    BLOB_KEY_PREFIX = "captcha/snapshots/"
    Capture = Data.define(:token, :oversize)

    class << self
      def capture(request)
        Captcha::OriginalRequestVerifier.verify!(request)
        files, oversize = persist_files(request)
        return Capture.new(token: nil, oversize: true) if oversize

        token = SecureRandom.urlsafe_base64(32)
        payload = {
          "ip" => (request.remote_ip.presence || request.ip).to_s,
          "binding" => Captcha::SessionBinding.digest(request.session, create: true),
          "origin" => request.base_url,
          "headers" => %w[HTTP_ORIGIN HTTP_REFERER HTTP_X_CSRF_TOKEN].index_with { |name| request.get_header(name) },
          "method" => request.request_method,
          "path" => request.path,
          "path_info" => request.path_info,
          "script_name" => request.script_name.to_s,
          "query" => request.query_string.to_s,
          "content_type" => request.content_type.to_s,
          "params" => scalar_params(request),
          "files" => files
        }
        cache.write(key(token), payload, expires_in: Captcha::ThrottlePresets::SNAPSHOT_TTL)
        Capture.new(token: token, oversize: false)
      end

      def take!(token, request:, path: nil, query: nil)
        return nil if token.blank?

        cache_key = key(token)
        payload = cache.read(cache_key)
        return nil if payload.blank?
        return nil unless payload["ip"].to_s == request.remote_ip.to_s
        return nil unless Captcha::SessionBinding.matches?(request.session, payload["binding"])
        return nil unless payload["origin"] == request.base_url
        return nil if path.present? && payload["path"].to_s != path.to_s
        return nil if !query.nil? && payload["query"].to_s != query.to_s
        return nil unless cache.delete(cache_key)

        payload
      end

      def prune_orphans!(older_than: Captcha::ThrottlePresets::SNAPSHOT_TTL.ago)
        ActiveStorage::Blob.unattached
                           .where("key LIKE ?", "#{BLOB_KEY_PREFIX}%")
                           .where(created_at: ...older_than)
                           .find_each(&:purge)
      end

      def cookie_path(script_name: "")
        "#{script_name}/captcha/challenge"
      end

      def cookie_header(token, script_name: "")
        {
          value: token,
          path: cookie_path(script_name: script_name),
          httponly: true,
          same_site: "Lax",
          max_age: Captcha::ThrottlePresets::SNAPSHOT_TTL.to_i
        }
      end

      def cache
        Captcha::ThrottleRegistry.store
      end

      private

      def key(token)
        "#{PREFIX}:#{token}"
      end

      def scalar_params(request)
        request.POST.each_with_object({}) do |(name, value), hash|
          next if value.respond_to?(:tempfile)

          hash[name.to_s] = value
        end
      rescue StandardError
        {}
      end

      def persist_files(request)
        files = {}
        created = []
        request.POST.each do |name, value|
          uploads = Array(value).select { |item| item.respond_to?(:tempfile) }
          next if uploads.empty?

          blobs = uploads.map do |upload|
            if upload.size.to_i > Captcha::ThrottlePresets::MAX_FILE_BYTES
              purge_created(created)
              return [{}, true]
            end

            blob = ActiveStorage::Blob.create_and_upload!(
              io: upload.tempfile,
              filename: upload.original_filename.presence || "upload",
              content_type: upload.content_type.presence || "application/octet-stream",
              key: "#{BLOB_KEY_PREFIX}#{SecureRandom.uuid}"
            )
            created << blob
            { "signed_id" => blob.signed_id, "filename" => blob.filename.to_s, "content_type" => blob.content_type }
          end
          files[name.to_s] = blobs
        end
        [files, false]
      rescue StandardError
        purge_created(created)
        [{}, true]
      end

      def purge_created(blobs)
        Array(blobs).each do |blob|
          blob.purge
        rescue StandardError
          nil
        end
      end
    end
  end
end
