# frozen_string_literal: true

module Dashboard
  class Home
    METRIC_ICONS = {
      "entities" => "M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375",
      "pages" => "M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125 1.125V11.25a9 9 0 00-9-9z",
      "modules" => "M21 7.5l-9-5.25L3 7.5m18 0l-9 5.25m9-5.25v9l-9 5.25M3 7.5l9 5.25M3 7.5v9l9 5.25m0-9v9",
      "users" => "M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z"
    }.freeze

    ACTION_ICONS = {
      "create_entity" => METRIC_ICONS.fetch("entities"),
      "new_page" => METRIC_ICONS.fetch("pages"),
      "enable_module" => METRIC_ICONS.fetch("modules"),
      "invite_user" => METRIC_ICONS.fetch("users")
    }.freeze

    SECONDARY_ACTIONS = [
      { key: "module_email_secondary", module_key: "email", index: 0 },
      { key: "module_payment_secondary", module_key: "payment", index: 1 },
      { key: "module_sms_secondary", module_key: "sms", index: 0 }
    ].freeze

    Result = Data.define(:metrics, :modules, :setup_items, :recent_pages, :recent_entities, :actions)

    def self.call(customer:)
      new(customer).call
    end

    def initialize(customer)
      @customer = customer
      @cid = customer.id
    end

    def call
      stats = LandingStats.for(@customer).to_h
      modules = ModuleCards.call(customer: @customer)
      Result.new(
        metrics: metrics(stats),
        modules: modules,
        setup_items: setup_items(stats),
        recent_pages: recent_pages,
        recent_entities: recent_entities,
        actions: actions(modules)
      )
    end

    private

    def metrics(stats)
      pages = stats[:pages] || {}
      [
        Metric.new(
          key: "entities",
          label: I18n.t("admin_misc.dashboard.stats.entities"),
          value: stats[:entities],
          sub_label: nil,
          icon: METRIC_ICONS.fetch("entities"),
          href: "/#{@cid}/admin/domains"
        ),
        Metric.new(
          key: "pages",
          label: I18n.t("admin_misc.dashboard.stats.pages"),
          value: pages[:total],
          sub_label: I18n.t("admin_misc.dashboard.pages_sub_label", count: pages[:launched].to_i),
          icon: METRIC_ICONS.fetch("pages"),
          href: "/#{@cid}/admin/domains"
        ),
        Metric.new(
          key: "modules",
          label: I18n.t("admin_misc.dashboard.stats.modules"),
          value: stats[:modules_enabled],
          sub_label: nil,
          icon: METRIC_ICONS.fetch("modules"),
          href: "/#{@cid}/admin/maintenance/modules"
        ),
        Metric.new(
          key: "users",
          label: I18n.t("admin_misc.dashboard.stats.users"),
          value: stats[:users],
          sub_label: nil,
          icon: METRIC_ICONS.fetch("users"),
          href: "/#{@cid}/admin/modules/authentication/users"
        )
      ]
    end

    def setup_items(stats)
      pages = stats[:pages] || {}
      [
        ["create_entity", stats[:entities].to_i.positive?, entity_authoring_path],
        ["launch_page", pages[:launched].to_i.positive?, "/#{@cid}/admin/domains"],
        ["enable_module", optional_module_enabled?, "/#{@cid}/admin/maintenance/modules"],
        ["invite_user", stats[:users].to_i > 1, "/#{@cid}/admin/modules/authentication/users/new"]
      ].map do |key, done, href|
        SetupItem.new(
          key: key,
          label: I18n.t("admin_misc.dashboard.setup.items.#{key}"),
          done: done,
          href: href
        )
      end
    end

    # Tenant admins create entities through the assistant; only the platform
    # owner uses the manual form in Maintenance.
    def entity_authoring_path = "/#{@cid}/admin/assistant"

    def recent_pages
      Page.visible.where(customer_id: [@cid, nil]).order(updated_at: :desc).limit(5)
          .pluck(:id, :name, :launched, :updated_at)
          .map do |id, name, launched, updated_at|
        RecentItem.new(
          name: name,
          href: "/#{@cid}/admin/pages/#{id}",
          badge: launched ? "live" : "draft",
          updated_at: updated_at
        )
      end
    end

    def recent_entities
      Entity.visible.non_bridge.where(customer_id: [@cid, nil]).order(updated_at: :desc).limit(5)
            .pluck(:id, :name, :display_label, :updated_at)
            .map do |id, name, display_label, updated_at|
        RecentItem.new(
          name: display_label.presence || name,
          href: "/#{@cid}/admin/entities/#{id}",
          badge: nil,
          updated_at: updated_at
        )
      end
    end

    def actions(modules)
      items = [
        core_action("create_entity", entity_authoring_path),
        core_action("new_page", "/#{@cid}/admin/maintenance/pages/new"),
        core_action("invite_user", "/#{@cid}/admin/modules/authentication/users/new")
      ]
      items << core_action("enable_module", "/#{@cid}/admin/maintenance/modules") if enable_module_available?

      modules.each do |card|
        break if items.size >= 8
        next if card.key == "authentication" || card.primary.nil?

        items << Action.new(
          key: "module_#{card.key}",
          label: card.primary.label,
          description: card.description,
          path: card.primary.href,
          icon: module_icon(card.key)
        )
      end

      SECONDARY_ACTIONS.each do |spec|
        break if items.size >= 8

        card = modules.find { |item| item.key == spec[:module_key] }
        link = card&.secondaries&.[](spec[:index])
        next unless link

        items << Action.new(
          key: spec[:key],
          label: link.label,
          description: card.description,
          path: link.href,
          icon: module_icon(spec[:module_key])
        )
      end

      items.first(8)
    end

    def core_action(key, path)
      Action.new(
        key: key,
        label: I18n.t("admin_misc.dashboard.actions.#{key}.label"),
        description: I18n.t("admin_misc.dashboard.actions.#{key}.description"),
        path: path,
        icon: ACTION_ICONS.fetch(key)
      )
    end

    def enable_module_available?
      assigned_ids = FeatureModules::Module.available_for_customer(@cid).select(:id)
      FeatureModules::Module.available.where(required: false).where.not(id: assigned_ids).exists?
    end

    def optional_module_enabled?
      FeatureModules::Module.enabled_for_customer(@cid).where(required: false).exists?
    end

    def module_icon(key)
      Admin::Maintenance::Platform::ModuleSettingsHelper::MODULE_ICON_PATHS.fetch(
        key.to_s,
        Admin::Maintenance::Platform::ModuleSettingsHelper::DEFAULT_MODULE_ICON_PATH
      )
    end
  end
end
