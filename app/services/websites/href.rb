# frozen_string_literal: true

require "addressable/uri"

module Websites
  # Resolves and validates hrefs stored on marketing sections.
  # Internal slugs use host-aware public paths; absolute links must be https.
  module Href
    SLUG = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
    # Root-relative path (single leading slash, never a protocol-relative
    # `//host`). Lets a marketing page link to its own app surfaces — sign-in,
    # sign-up, a member URL — without hard-coding a host.
    ROOT_RELATIVE = %r{\A/(?!/)[^\s]*\z}
    # Browsers normalize backslashes and strip controls during URL parsing.
    # Reject them on the raw value, before even stripping surrounding spaces.
    UNSAFE_HREF_CHARACTERS = /[\\\u0000-\u001f\u007f-\u009f]/

    module_function

    def valid?(value)
      s = value.to_s
      return false if s.match?(UNSAFE_HREF_CHARACTERS)

      s = s.strip
      return true if s.blank?
      return true if s.match?(SLUG)
      return true if s.match?(ROOT_RELATIVE)

      https?(s)
    end

    MEDIA_PATH = %r{\A/\d{8}/site/media/[^/]+\z}
    # Public, repository-bundled illustrations only; this does not allow SVG uploads.
    BUNDLED_ILLUSTRATION_PATH = %r{\A/site-images/anysys/anysys-[a-z0-9-]+\.svg\z}
    BUNDLED_PHOTO_PATH = %r{\A/site-images/anysys/anysys-photo-[a-z0-9-]+\.webp\z}

    def media?(value)
      s = value.to_s
      # Match the raw path so trimming cannot hide controls or surrounding spaces.
      return true if BUNDLED_ILLUSTRATION_PATH.match?(s) || BUNDLED_PHOTO_PATH.match?(s)

      s = s.strip
      return true if https?(s)
      return true if MEDIA_PATH.match?(s)

      false
    end

    def error_message(value)
      return if valid?(value)

      s = value.to_s.strip
      return I18n.t("website.errors.javascript_href") if s.downcase.start_with?("javascript:")

      I18n.t("website.errors.invalid_href")
    end

    def resolve(value, customer_id:, host: nil)
      s = value.to_s
      return if s.match?(UNSAFE_HREF_CHARACTERS)

      s = s.strip
      return if s.blank?
      return s if https?(s)
      return resolve_local_path(s, host: host) if s.match?(ROOT_RELATIVE)
      return PageShortcuts::PublicPath.website_slug(slug: s, customer_id: customer_id, host: host) if s.match?(SLUG)

      nil
    end

    # Translate only canonical public destinations. Addressable keeps repeated
    # query pairs and encoded fragments intact when only URI#path is replaced.
    def resolve_local_path(value, host:)
      uri = Addressable::URI.parse(value)
      if (match = uri.path.match(%r{\A/(\d{8})/site(?:/([a-z0-9]+(?:-[a-z0-9]+)*))?/?\z}))
        uri.path = if match[2]
          PageShortcuts::PublicPath.website_slug(slug: match[2], customer_id: match[1], host: host)
        else
          PageShortcuts::PublicPath.website_home(customer_id: match[1], host: host)
        end
      elsif (match = uri.path.match(%r{\A/(\d{8})/page/([a-f0-9-]+)\z}))
        path = PageShortcuts::PublicPath.public_page_uuid(uuid: match[2], customer_id: match[1], host: host)
        uri.path = path if path
      end
      uri.to_s
    rescue Addressable::URI::InvalidURIError
      value
    end

    def https?(value)
      uri = Addressable::URI.parse(value.to_s.strip)
      return false unless uri&.scheme.to_s.downcase == "https"

      host = uri.host.to_s
      host.include?(".") || host.match?(/\A\[[^\]]+\]\z/)
    rescue Addressable::URI::InvalidURIError, TypeError
      false
    end
  end
end
