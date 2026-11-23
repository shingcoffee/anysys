# frozen_string_literal: true

module AccessPoints
  class RouteProvider < Provider
    HTTP_VERB_TO_ACTION = {
      "GET"    => :read,
      "POST"   => :create,
      "PATCH"  => :update,
      "PUT"    => :update,
      "DELETE" => :destroy
    }.freeze

    ROUTE_GROUP_I18N = {
      "admin"                       => "admin",
      "admin.maintenance"           => "maintenance",
      "admin.maintenance.platform"  => "platform",
      "admin.settings"              => "settings",
      "admin.misc"                  => "misc"
    }.freeze

    def group_key   = "admin.routes"
    def group_label = I18n.t("admin_settings.access_points.groups.admin_routes")

    def label_for_group(key)
      route_group_label(key)
    end

    def call(customer_id:)
      grouped = Hash.new { |h, k| h[k] = Set.new }

      Rails.application.routes.routes.each do |route|
        path = route.path.spec.to_s
        next unless admin_path?(path)

        controller = route.defaults[:controller]
        next if controller.blank?
        next if OwnerOnlySurfaces.controller?(controller)

        verb_str = http_verb(route)
        action   = HTTP_VERB_TO_ACTION[verb_str]
        next if action.nil?

        grouped[controller] << action
      end

      grouped.map do |controller_path, actions|
        Descriptor.new(
          subject_type: "Route",
          subject_key:  controller_path,
          subject_id:   nil,
          actions:      actions.to_a.sort_by(&:to_s),
          group_key:    derive_group_key(controller_path),
          label:        humanize(controller_path),
          description:  nil
        )
      end
    end

    private

    def admin_path?(path)
      path.include?("/admin")
    end

    def http_verb(route)
      verb = route.verb
      verb.is_a?(Regexp) ? verb.source.match(/[A-Z]+/)&.to_s : verb.to_s
    end

    def derive_group_key(controller_path)
      parts = controller_path.split("/")
      case parts
      in ["admin", "maintenance", "platform", *_]
        "admin.maintenance.platform"
      in ["admin", "maintenance", *_]
        "admin.maintenance"
      in ["admin", "modules", mod, *_]
        "admin.modules.#{mod}"
      in ["admin", "settings", "modules", mod, *_]
        "admin.settings.modules.#{mod}"
      in ["admin", "settings", *_]
        "admin.settings"
      in ["admin", *_]
        "admin"
      else
        "admin.misc"
      end
    end

    def route_group_label(key)
      if (i18n_key = ROUTE_GROUP_I18N[key])
        I18n.t("admin_settings.access_points.route_groups.#{i18n_key}")
      elsif (mod = key[/\Aadmin\.modules\.(.+)\z/, 1])
        module_display_name(mod)
      elsif (mod = key[/\Aadmin\.settings\.modules\.(.+)\z/, 1])
        I18n.t("admin_settings.access_points.route_groups.settings_module", name: module_display_name(mod))
      else
        I18n.t("admin_settings.access_points.route_groups.misc")
      end
    end

    def module_display_name(key)
      FeatureModules::Module.find_by(key: key)&.display_name || key.to_s.tr("_", " ")
    end

    def humanize(controller_path)
      if (key = SmsRouteLabels.key_for(controller_path))
        return I18n.t(key)
      end
      if controller_path.start_with?("admin/modules/sms/")
        key = controller_path.split("/").last
        return I18n.t("sms_campaign_http.access_points.#{key}") if I18n.exists?("sms_campaign_http.access_points.#{key}")
      end
      controller_path.split("/").last.to_s.humanize.titleize
    end
  end
end
