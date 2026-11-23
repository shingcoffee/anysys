# frozen_string_literal: true

require "openssl"
require "base64"
require "securerandom"
require "cgi"

module Vendor
  # Vendor::AliyunRpc
  #
  # Single app-level implementation of Aliyun's RPC-style "v1.0 / HMAC-SHA1"
  # request signature. Previously each Aliyun adapter (speech-to-text, captcha,
  # SMS) carried its own copy of the nonce, the canonical query builder, the
  # `POST&%2F&…` string-to-sign and the CGI.escape fixups — three chances to
  # drift apart on a security-critical code path, which AGENTS.md forbids.
  #
  # It stays hand-rolled on purpose: there is no maintained Ruby SDK for Aliyun
  # RPC APIs (the official `aliyun-sdk` gem covers OSS only), so per AGENTS.md
  # the hand-rolled protocol code is confined to ONE thin service with a single
  # public interface and a golden signing spec.
  #
  # Callers differ only in `Version`, `RegionId` and where the secret lives, so
  # those are parameters — the algorithm itself is not.
  #
  # @example
  #   params = Vendor::AliyunRpc.common_params(
  #     access_key_id: "AKID", region_id: "cn-shanghai", version: "2019-02-28"
  #   ).merge("Action" => "CreateToken")
  #   signed = Vendor::AliyunRpc.sign(params, secret: "AKS")
  #   signed["Signature"] # => Base64 HMAC-SHA1
  class AliyunRpc
    SIGNATURE_METHOD  = "HMAC-SHA1"
    SIGNATURE_VERSION = "1.0"
    DEFAULT_FORMAT    = "JSON"
    DEFAULT_HTTP_VERB = "POST"
    TIMESTAMP_FORMAT  = "%Y-%m-%dT%H:%M:%SZ"

    class << self
      # The RPC common parameters every Action shares. `SignatureNonce` and
      # `Timestamp` are generated per call, so a signed request is not replayable.
      def common_params(access_key_id:, region_id:, version:, format: DEFAULT_FORMAT)
        {
          "AccessKeyId"      => access_key_id.to_s,
          "Format"           => format.to_s,
          "RegionId"         => region_id.to_s,
          "SignatureMethod"  => SIGNATURE_METHOD,
          "SignatureNonce"   => SecureRandom.uuid,
          "SignatureVersion" => SIGNATURE_VERSION,
          "Timestamp"        => Time.now.utc.strftime(TIMESTAMP_FORMAT),
          "Version"          => version.to_s
        }
      end

      # THE signing entry point. Every adapter calls this and nothing else —
      # merging "Signature" in here (rather than in each caller) is what keeps
      # the signer swappable without touching captcha, SMS or speech-to-text.
      #
      # @return [Hash] a copy of the params with the computed "Signature" merged in.
      def sign(params, secret:, http_verb: DEFAULT_HTTP_VERB)
        params.merge("Signature" => signature(params, secret: secret, http_verb: http_verb))
      end

      # ------------------------------------------------------------------
      # Algorithm steps. `common_params` + `sign` are the supported
      # interface; the methods below are exposed only so the golden spec can
      # pin each step of a security-critical computation independently.
      # Adapters must not call them.
      # ------------------------------------------------------------------

      def signature(params, secret:, http_verb: DEFAULT_HTTP_VERB)
        digest = OpenSSL::HMAC.digest(
          "SHA1", "#{secret}&", string_to_sign(params, http_verb: http_verb)
        )
        Base64.strict_encode64(digest)
      end

      def string_to_sign(params, http_verb: DEFAULT_HTTP_VERB)
        "#{http_verb}&#{encode('/')}&#{encode(canonical_query(params))}"
      end

      # Sorted, percent-encoded `k=v` pairs joined with "&". Aliyun sorts by the
      # raw parameter name, which for the ASCII-only RPC parameter set is the
      # same as sorting the encoded name.
      def canonical_query(params)
        params.sort.map { |key, value| "#{encode(key)}=#{encode(value)}" }.join("&")
      end

      # Aliyun's percent-encoding is RFC 3986, which CGI.escape does not quite
      # produce: space must be %20 (not +), "*" must be escaped, and "~" must
      # NOT be.
      def encode(value)
        CGI.escape(value.to_s).gsub("+", "%20").gsub("*", "%2A").gsub("%7E", "~")
      end
    end
  end
end
