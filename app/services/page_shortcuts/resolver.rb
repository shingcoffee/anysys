# frozen_string_literal: true

module PageShortcuts
  module Resolver
    CACHE_KEY = "page_shortcuts.resolutions"

    module_function

    # Share only the per-request resolution cache used by Journey constraints.
    # The captcha gate runs first, but must not mark a route as matched or inject
    # tenant/target parameters; RouteContext remains responsible for that.
    def cached_resolve(request)
      cache = request.env[CACHE_KEY] ||= {}
      key = [request.host, request.path_info]
      cache[key] = resolve(request) unless cache.key?(key)
      cache[key]
    end

    def resolve(request)
      return unless request.get? || request.head? || request.post?

      path = normalize_request_path(request.path_info)
      return unless path && original_path_valid?(request, path)

      first, remaining = path.delete_prefix("/").split("/", 2)
      if (cid = PathPolicy.customer_id(first))
        relative = remaining.present? ? "/#{remaining}" : "/"
      else
        cid = Hosts.customer_id(request.host)
        relative = path
      end
      return if PathPolicy.reserved?(relative) || !Customer.exists?(id: cid)

      shortcut = PageShortcut.for_customer(cid).find_by(path: relative)
      if shortcut
        # A stale explicit mapping fails closed; never fall through to a new home.
        return if Collisions.shortcut_conflict?(path: relative, customer_id: cid,
                                               target_type: shortcut.target_type, target_id: shortcut.target_id)
        target = TargetEligibility.resolve(type: shortcut.target_type, id: shortcut.target_id, customer_id: cid)
        return if request.post? && target&.target_type != "Page"

        return target
      end

      return if request.post?
      return unless PathPolicy.automatic?(relative)

      scope = TargetEligibility.website_pages(customer_id: cid)
      page_id = if relative == "/"
        scope.where(home: true).pick(:id)
      else
        scope.where(home: false, slug: relative.delete_prefix("/")).pick(:id)
      end
      TargetEligibility.resolve(type: "WebsitePage", id: page_id, customer_id: cid) if page_id
    end

    # A nil public target does not mean an explicit root mapping is absent.
    # Keep Target/nil as the resolver API; this fixed root-only constraint makes
    # unavailable mappings terminal without sending a sentinel to captcha/link code.
    def unavailable_root?(request)
      return false unless request.get? || request.head?
      return false unless PathPolicy.normalize(request.path_info, leading_slash: false) == "/"
      return true unless original_path_valid?(request, "/")
      return false if cached_resolve(request)

      cid = Hosts.customer_id(request.host)
      return true if PageShortcut.for_customer(cid).exists?(path: "/")
      return false if Customer.exists?(id: cid)

      # An absent shared default is normal during bootstrap. Dedicated hosts
      # are explicit tenant selections; known inactive defaults also fail closed.
      Hosts.dedicated?(request.host) || Customer.unscoped.exists?(id: cid)
    end

    # Journey normalizes repeated slashes before calling request constraints.
    # Servers exposing REQUEST_URI let us reject the original malformed spelling
    # too. Query strings are deliberately independent of destination selection.
    def original_path_valid?(request, normalized)
      raw = request.get_header("REQUEST_URI")
      return true if raw.nil?

      uri = Addressable::URI.parse(raw)
      return false if uri.scheme || uri.authority || uri.fragment

      path = uri.path
      mount = request.script_name.to_s
      return false unless mount.empty? || path.start_with?("#{mount}/") || path == mount

      path = path.delete_prefix(mount) if mount.present?
      path = "/" if path.empty?
      normalize_request_path(path) == normalized
    rescue Addressable::URI::InvalidURIError, ArgumentError
      false
    end
    private_class_method :original_path_valid?

    # The stored limit is customer-relative. Recognize exactly one canonical
    # eight-digit prefix before validating the suffix; never decode, strip a
    # malformed prefix, or normalize away separators/traversal in either part.
    def normalize_request_path(value)
      return unless value.is_a?(String) && value.valid_encoding? && value.start_with?("/")
      return if value.bytesize > PathPolicy::MAX_LENGTH + 9

      first = value.delete_prefix("/").split("/", 2).first
      return PathPolicy.normalize(value, leading_slash: false) unless PathPolicy.customer_id(first)

      prefix = "/#{first}"
      relative = value.delete_prefix(prefix)
      relative = "/" if relative.empty?
      normalized = PathPolicy.normalize(relative, leading_slash: false)
      "#{prefix}#{normalized}" if normalized
    end
    private_class_method :normalize_request_path
  end
end
