# frozen_string_literal: true

module PageShortcuts
  # Journey selects fixed destinations; the resolver never rewrites the Rack
  # path or supplies a controller/action from user input.
  class RouteConstraint
    MATCH_KEY = "page_shortcuts.route_match"

    def self.matches?(request, controller:, action:)
      target = Resolver.cached_resolve(request)
      expected_action = action == "submit" ? "show" : action
      return false unless target && target.controller == controller && target.action == expected_action
      return false if action == "submit" && (controller != "public_pages" || target.target_type != "Page")

      # Only a successful constraint marks a mapped request. A cached result
      # from an earlier failed constraint must not affect the fallback route.
      request.env[MATCH_KEY] = { target: target, controller: controller, action: action }
      true
    end
  end
end
