# frozen_string_literal: true

module Captcha
  # A vendor outage permits one redirect continuation, never a reusable Grant.
  # The receipt is bound to the exact GET, origin, IP and encrypted session.
  class RequestPassage
    SESSION_KEY = "captcha_passage"
    TTL = 1.minute

    def self.store(request:, return_to:, allow: true, captcha_result: false)
      token = SecureRandom.urlsafe_base64(32)
      Captcha::ThrottleRegistry.store.write(key(token), {
        "binding" => Captcha::SessionBinding.digest(request.session, create: true),
        "ip" => request.remote_ip.to_s,
        "origin" => request.base_url,
        "return_to" => return_to,
        "allow" => allow,
        "captcha_result" => captcha_result
      }, expires_in: TTL)
      request.session[SESSION_KEY] = token
    end

    def self.take!(request)
      return false unless request.get?

      token = request.session[SESSION_KEY]
      return false unless token.is_a?(String) && token.present?

      store = Captcha::ThrottleRegistry.store
      payload = store.read(key(token))
      unless payload
        request.session.delete(SESSION_KEY)
        return false
      end
      return false unless Captcha::SessionBinding.matches?(request.session, payload["binding"])
      return false unless payload.values_at("ip", "origin", "return_to") ==
        [request.remote_ip.to_s, request.base_url, request.fullpath]
      return false unless store.delete(key(token))

      request.session.delete(SESSION_KEY)
      payload
    end

    # Carry only the verification RESULT across further same-origin redirects.
    # The outage bypass is never forwarded to another request or destination.
    def self.forward(request:, location:, captcha_result:)
      return if location.blank?

      uri = URI.join(request.base_url, location)
      return unless uri.userinfo.nil? &&
        [uri.scheme, uri.host, uri.port] == [request.scheme, request.host, request.port]

      destination = uri.path + (uri.query.present? ? "?#{uri.query}" : "")
      store(request: request, return_to: destination, allow: false, captcha_result: captcha_result)
    rescue URI::InvalidURIError
      nil
    end

    def self.key(token)
      "captcha:passage:#{token}"
    end
    private_class_method :key
  end
end
