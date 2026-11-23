# frozen_string_literal: true

module Captcha
  # Maps a request path to a throttle rule. Most specific stored row wins;
  # skipped rows pass through without the implicit default. Unmatched paths
  # are not challenged. Only /captcha/challenge is hard-skipped (loop guard).
  class UrlMatcher
    PAGE_PATH = %r{\A/(\d+)/page/([0-9a-fA-F-]{36})\z}
    SKIP_PREFIXES = %w[
      /captcha/challenge
    ].freeze

    class << self
      def for_request(request)
        for_path(request.path_info, request: request)
      end

      # A canonical page rule is authoritative across all its aliases. Resolve
      # only from host/path/method, never query/body identity or Current. Keep
      # the original request intact for challenge return_to and POST snapshots.
      def for_path(path, request: nil)
        return match(path) unless request

        context = request_for_path(path, request)
        target = if context.equal?(request)
          PageShortcuts::Resolver.cached_resolve(context)
        else
          PageShortcuts::Resolver.resolve(context)
        end
        canonical_rule = match(target.canonical_path) if target
        return canonical_rule || match(context.path_info) if target

        match(context.path_info)
      end

      def match(path)
        path = path.to_s.chomp("/")
        path = "/" if path.blank?
        return nil if skip?(path)

        path = canonical_route_path(path)
        match_stored(path) || page_rule(path) || surface_rule(path)
      end

      def skip?(path)
        return true if SKIP_PREFIXES.any? { |s| path == s.chomp("/") || path.start_with?(s) }

        false
      end

      def template_match?(template, path)
        Captcha::PathTemplate.match?(template, path)
      end

      private

      # Alias resolution sees the full spelling first. Only strip the optional
      # Rails format on known page/surface routes, never arbitrary dotted slugs.
      def canonical_route_path(path)
        base = path.to_s.sub(/\.[^\/.]+\z/, "")
        return path unless base != path && (PAGE_PATH.match?(base) || Captcha::SurfaceCatalog.matching_surface(base))

        base
      end

      # Challenge return_to contains the external, possibly mounted path. Its
      # destination is a read context even when the challenge itself is a POST.
      def request_for_path(path, request)
        return request if path == request.path_info

        mount = request.script_name.to_s
        router_path = path.to_s
        if mount.present? && (router_path == mount || router_path.start_with?("#{mount}/"))
          router_path = router_path.delete_prefix(mount).presence || "/"
        end
        env = request.env.merge("PATH_INFO" => router_path, "REQUEST_METHOD" => "GET",
                                "QUERY_STRING" => "", "REQUEST_URI" => path.to_s)
        ActionDispatch::Request.new(env)
      end

      def match_stored(path)
        exact = stored_row("exact", path)
        return rule_from_row(exact, fail_closed: path_fail_closed?(path)) if exact

        templates = stored_rows.select { |row| row.match_kind == "template" && template_match?(row.url_pattern, path) }
        best = templates.max_by { |row| row.url_pattern.length }
        return nil unless best

        rule_from_row(best, fail_closed: path_fail_closed?(path) || surface_fail_closed?(best.surface_key))
      end

      def page_rule(path)
        match = PAGE_PATH.match(path)
        return nil unless match

        info = Captcha::ThrottleRegistry.page_index[match[2]]
        return default_rule(path, fail_closed: false) if info.nil?
        return nil unless info["launched"]

        if info["shared"]
          pattern = "/:customer_id/page/#{match[2]}"
          stored = stored_row("template", pattern)
          return rule_from_row(stored, fail_closed: false) if stored

          return default_rule(pattern, fail_closed: false)
        end

        default_rule("/#{info['customer_id']}/page/#{match[2]}", fail_closed: false)
      end

      def surface_rule(path)
        surface = Captcha::SurfaceCatalog.matching_surface(path)
        return nil unless surface

        stored = stored_rows.find do |row|
          row.match_kind == "template" && (row.surface_key == surface.key || row.url_pattern == surface.path)
        end
        return rule_from_row(stored, fail_closed: surface.fail_closed?) if stored

        default_rule(surface.path, fail_closed: surface.fail_closed?, surface_key: surface.key)
      end

      def stored_rows
        Array(Captcha::ThrottleRegistry.rules)
      end

      def stored_row(match_kind, url_pattern)
        stored_rows.find { |row| row.match_kind == match_kind && row.url_pattern == url_pattern }
      end

      def default_rule(pattern, fail_closed:, surface_key: nil)
        defaults = Captcha::ThrottlePresets.default_rule
        Captcha::ThrottleRegistry::Rule.new(
          pattern: pattern,
          match_kind: pattern.include?(":") ? "template" : "exact",
          limit_count: defaults[:limit_count],
          period_seconds: defaults[:period_seconds],
          every_hit: false,
          skipped: false,
          fail_closed: fail_closed,
          surface_key: surface_key,
          page_id: nil
        )
      end

      def rule_from_row(row, fail_closed:)
        Captcha::ThrottleRegistry::Rule.new(
          pattern: row.url_pattern,
          match_kind: row.match_kind,
          limit_count: row.limit_count,
          period_seconds: row.period_seconds,
          every_hit: row.every_hit,
          skipped: row.skipped == true,
          fail_closed: fail_closed,
          surface_key: row.surface_key,
          page_id: row.page_id
        )
      end

      def surface_fail_closed?(key)
        return false if key.blank?

        Captcha::SurfaceCatalog.find(key)&.fail_closed? == true
      end

      def path_fail_closed?(path)
        Captcha::SurfaceCatalog.matching_surface(path)&.fail_closed? == true
      end
    end
  end
end
