# frozen_string_literal: true

require "addressable/uri"

module PageShortcuts
  # URI parsing belongs to Addressable; these are application namespace and
  # tenant-relative slug rules, shared by writes, constraints and public links.
  module PathPolicy
    CUSTOMER_ID = /\A[1-9][0-9]{7}\z/
    SEGMENT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
    ALIAS_SEGMENT = /\A[a-z0-9]+(?:[.-][a-z0-9]+)*\z/
    MAX_LENGTH = 255
    RESERVED_SEGMENTS = %w[
      admin member auth authentication oauth locale up health healthz readyz
      captcha payment payments sms email emails unsubscribe page pages site
      site-images assets rails media uploads storage active-storage
      cable api settings maintenance modules manifest service-worker
      sign-in sign-out sign-up login logout signup users .well-known
    ].freeze

    module_function

    # Form input may omit the leading slash or contain one trailing slash.
    # Nothing is decoded or URI-normalized: encoded separators/traversal fail.
    def normalize(value, leading_slash: true)
      return unless value.is_a?(String) && value.valid_encoding?
      return if value.empty? || value.bytesize > MAX_LENGTH

      uri = Addressable::URI.parse(value)
      return if uri.scheme || uri.authority || uri.query || uri.fragment
      return unless uri.path == value
      return if !leading_slash && !value.start_with?("/")

      path = value.start_with?("/") ? value : "/#{value}"
      path = path.delete_suffix("/") unless path == "/"
      return if path.bytesize > MAX_LENGTH
      return "/" if path == "/"
      return unless path.delete_prefix("/").split("/", -1).all? { |segment| ALIAS_SEGMENT.match?(segment) }

      path
    rescue Addressable::URI::InvalidURIError, ArgumentError
      nil
    end

    def reserved?(path)
      first = path.to_s.split("/")[1]
      base = first.to_s.split(".").first.to_s
      # Numeric first segments are tenant addressing, never tenant-relative aliases.
      first.nil? ? false : RESERVED_SEGMENTS.include?(first) || RESERVED_SEGMENTS.include?(base) || base.match?(/\A[0-9]+\z/)
    end

    def automatic?(path)
      path == "/" || (normalize(path, leading_slash: false) == path &&
        !reserved?(path) && path.count("/") == 1 && SEGMENT.match?(path.delete_prefix("/")))
    end

    def customer_id(value)
      value.to_s.to_i if CUSTOMER_ID.match?(value.to_s)
    end
  end
end
