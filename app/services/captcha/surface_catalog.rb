# frozen_string_literal: true

module Captcha
  # Discovers platform public HTML forms from the route set and merges them
  # with a locked table of known surfaces. Locked keys always exist even if
  # the walk is flaky; extra GET+mutate public controllers land in :other.
  class SurfaceCatalog
    Surface = Data.define(:key, :group, :path, :fail_closed, :name_i18n_key) do
      def fail_closed? = fail_closed
    end

    LOCKED = [
      { key: "authentication/sessions",               group: :authentication, path: "/auth/sign_in",                   fail_closed: true },
      { key: "authentication/customer_registrations", group: :authentication, path: "/auth/sign_up",                   fail_closed: true },
      { key: "authentication/passwords",              group: :authentication, path: "/auth/password/new",              fail_closed: true },
      { key: "authentication/confirmations",          group: :authentication, path: "/auth/confirmation/new",          fail_closed: true },
      { key: "authentication/registrations#sign_up",  group: :authentication, path: "/:customer_id/auth/sign_up",      fail_closed: true },
      { key: "authentication/registrations#account",  group: :account,         path: "/auth/edit",                      fail_closed: false },
      { key: "authentication/mfa_sessions",           group: :mfa,             path: "/:customer_id/auth/mfa/session",  fail_closed: true },
      { key: "authentication/mfa_setups",             group: :mfa,             path: "/:customer_id/auth/mfa/setup",    fail_closed: true },
      { key: "authentication/mfa_recoveries",         group: :mfa,             path: "/:customer_id/auth/mfa_recovery/new", fail_closed: true },
      { key: "emails/unsubscribes",                   group: :email,           path: "/unsubscribe/:token",             fail_closed: false },
      { key: "oauth/authorizations",                  group: :oauth,           path: "/oauth/authorize",                fail_closed: false },
      { key: "payments/checkouts",                    group: :payments,        path: "/:customer_id/payments/checkout", fail_closed: false }
    ].freeze

    # Controllers that map to a locked key (including splits). Do not re-emit
    # these as :other. sign_in_links is merged into authentication/sessions.
    CLAIMED_CONTROLLERS = (
      LOCKED.map { |row| row[:key].split("#", 2).first } + %w[authentication/sign_in_links]
    ).uniq.freeze

    DENYLIST_EXACT = %w[
      view_components
      payments/webhooks
      sms/webhooks
      emails/webhooks
      emails/tracking
      oauth/discovery
      oauth/userinfo
      doorkeeper/tokens
      locales
      rails/health
      public_pages
    ].freeze

    DENYLIST_PREFIXES = %w[rails/ turbo/ action_mailbox active_storage].freeze
    MUTATE_VERBS = %w[POST PATCH PUT].freeze

    class << self
      def surfaces
        @surfaces ||= (locked_surfaces + other_surfaces).freeze
      end

      def reset!
        @surfaces = nil
      end

      def find(key)
        surfaces.find { |surface| surface.key == key.to_s }
      end

      # Request path → catalog surface for the throttle gate. Templates
      # (`/:customer_id/...`) match one segment; sibling form URLs (e.g.
      # `/auth/password` next to `/auth/password/new`) map to the same surface.
      def matching_surface(path)
        path = path.to_s
        surfaces.find { |surface| path_matches_surface?(path, surface) }
      end

      private

      def path_matches_surface?(path, surface)
        templates = [surface.path] + alias_paths_for(surface)
        templates.any? do |template|
          Captcha::PathTemplate.match?(template, path) || sibling_form_match?(template, path)
        end
      end

      def alias_paths_for(surface)
        case surface.key
        when "authentication/sessions"
          %w[/auth/sign_in_link /auth/sign_in_link/check_email]
        when "authentication/passwords"
          %w[/auth/password /auth/password/edit]
        when "authentication/confirmations"
          %w[/auth/confirmation]
        when "authentication/registrations#sign_up"
          %w[/:customer_id/auth]
        when "authentication/customer_registrations"
          # /resend re-sends the signup email and becomes reachable once
          # session[:customer_signup_email] is set, i.e. after a single
          # captcha-solved #create. Without this alias it matched no surface
          # at all, so the gate let every resend through — on a surface
          # explicitly marked fail_closed. /confirm stays uncovered on
          # purpose: it is a token click, not a form post.
          %w[/auth/sign_up/resend]
        else
          []
        end
      end

      def sibling_form_match?(template, path)
        return false unless template.end_with?("/new") || template.end_with?("/edit")

        Captcha::PathTemplate.match?(template.sub(%r{/(new|edit)\z}, ""), path)
      end

      def locked_surfaces
        LOCKED.map { |row| build_surface(**row) }
      end

      def other_surfaces
        discovered_candidates.filter_map do |controller, info|
          next if CLAIMED_CONTROLLERS.include?(controller)

          build_surface(
            key: controller,
            group: :other,
            path: info[:get_paths].first.to_s,
            fail_closed: false
          )
        end.sort_by(&:key)
      end

      def build_surface(key:, group:, path:, fail_closed:)
        Surface.new(
          key: key,
          group: group,
          path: path,
          fail_closed: fail_closed,
          name_i18n_key: "captcha.surfaces.#{key.to_s.gsub(%r{[/\#]}, '_')}"
        )
      end

      def discovered_candidates
        grouped = Hash.new { |h, k| h[k] = { verbs: Set.new, get_paths: [] } }

        Rails.application.routes.routes.each do |route|
          path = route.path.spec.to_s
          next if path.include?("/admin") || path.include?("/member")

          controller = route.defaults[:controller]
          next if controller.blank? || denylisted?(controller)

          verbs = http_verbs(route)
          next if verbs.empty?

          grouped[controller][:verbs].merge(verbs)
          grouped[controller][:get_paths] << strip_format(path) if verbs.include?("GET")
        end

        grouped.select do |_controller, info|
          info[:verbs].include?("GET") && (info[:verbs] & MUTATE_VERBS).any?
        end
      end

      def denylisted?(controller)
        return true if DENYLIST_EXACT.include?(controller)

        DENYLIST_PREFIXES.any? do |prefix|
          controller == prefix || controller.start_with?("#{prefix.delete_suffix('/')}/")
        end
      end

      def http_verbs(route)
        verb = route.verb
        source = verb.is_a?(Regexp) ? verb.source : verb.to_s
        source.scan(/[A-Z]+/)
      end

      def strip_format(path)
        path.sub("(.:format)", "")
      end
    end
  end
end
