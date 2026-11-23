# frozen_string_literal: true

module Admin
  module Dashboard
    # Admin Home command center: snapshot metrics, enabled modules, setup,
    # recents, and compact quick actions. Copy and destinations come from the
    # `home` DTO — this composer does not embed assistant chrome.
    class WorkspaceComponent < ApplicationComponent
      HEADER_ACTION_KEYS = %w[new_page create_entity].freeze

      METRIC_THEMES = {
        "entities" => {
          well: "bg-accent-subtle text-accent ring-accent-muted/70 group-hover:bg-accent group-hover:text-white group-hover:ring-accent",
          bar: "from-accent to-accent-hover",
          border: "hover:border-accent-muted"
        },
        "pages" => {
          well: "bg-info-subtle text-info ring-sky-200/80 group-hover:bg-info group-hover:text-white group-hover:ring-info",
          bar: "from-info to-sky-500",
          border: "hover:border-sky-300"
        },
        "modules" => {
          well: "bg-purple-50 text-purple-600 ring-purple-200/80 group-hover:bg-purple-600 group-hover:text-white group-hover:ring-purple-600",
          bar: "from-purple-500 to-purple-600",
          border: "hover:border-purple-300"
        },
        "users" => {
          well: "bg-success-subtle text-success ring-emerald-200/80 group-hover:bg-success group-hover:text-white group-hover:ring-success",
          bar: "from-success to-emerald-500",
          border: "hover:border-emerald-300"
        }
      }.freeze

      DEFAULT_METRIC_THEME = METRIC_THEMES.fetch("entities").freeze

      attr_reader :customer, :user, :home

      def initialize(customer:, user:, home:)
        @customer = customer
        @user = user
        @home = home
      end

      def metrics
        Array(home&.metrics)
      end

      def modules
        Array(home&.modules)
      end

      def setup_items
        Array(home&.setup_items)
      end

      def recent_pages
        Array(home&.recent_pages)
      end

      def recent_entities
        Array(home&.recent_entities)
      end

      def actions
        Array(home&.actions)
      end

      def header_actions
        HEADER_ACTION_KEYS.filter_map { |key| actions.find { |action| action.key.to_s == key } }
      end

      def rail_actions
        actions - header_actions
      end

      def primary_header_action?(action)
        action.key.to_s == HEADER_ACTION_KEYS.last
      end

      def metric_value(metric)
        helpers.number_with_delimiter(metric.value.to_i)
      end

      def show_setup?
        setup_items.any? && !setup_items.all?(&:done)
      end

      def setup_done_count
        setup_items.count(&:done)
      end

      def setup_progress_percent
        return 0 if setup_items.empty?

        (setup_done_count * 100.0 / setup_items.size).round
      end

      def metric_theme(metric)
        METRIC_THEMES.fetch(metric.key.to_s, DEFAULT_METRIC_THEME)
      end

      def action_icon_classes(action)
        case action.key.to_s
        when "invite_user", /\Amodule_sms/
          "bg-success-subtle text-success ring-1 ring-inset ring-emerald-200/70 group-hover:bg-success group-hover:text-white group-hover:ring-success"
        when "enable_module", /\Amodule_website/
          "bg-purple-50 text-purple-600 ring-1 ring-inset ring-purple-200/70 group-hover:bg-purple-600 group-hover:text-white group-hover:ring-purple-600"
        when "new_page", /\Amodule_email/
          "bg-info-subtle text-info ring-1 ring-inset ring-sky-200/70 group-hover:bg-info group-hover:text-white group-hover:ring-info"
        else
          "bg-accent-subtle text-accent ring-1 ring-inset ring-accent-muted/70 group-hover:bg-accent group-hover:text-white group-hover:ring-accent"
        end
      end
    end
  end
end
