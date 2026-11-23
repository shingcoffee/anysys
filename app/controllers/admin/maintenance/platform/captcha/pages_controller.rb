# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  module Captcha
    # Owner-only throttle for a shared (customer_id NULL) public page, plus the
    # captcha module's Resources surface: the catalogue of public URLs and shared
    # pages whose access throttle decides when a challenge appears.
    class PagesController < ThrottlesController
      def index
        @feature_module = ::FeatureModules::Module.find_by!(key: "captcha")
        @surfaces = ::Captcha::SurfaceCatalog.surfaces.map do |surface|
          {
            key: surface.key,
            group: surface.group.to_s,
            path: surface.path,
            fail_closed: surface.fail_closed?,
            **::Captcha::ThrottleRegistry.display_for(match_kind: "template", url_pattern: surface.path)
          }
        end
        @shared_pages = ::Page.shared.for_audience("public").by_name.map do |page|
          pattern = "/:customer_id/page/#{page.public_uuid}"
          {
            id: page.id,
            name: page.name,
            public_path: pattern,
            launched: page.launched?,
            fail_closed: false,
            update_url: admin_maintenance_platform_module_settings_captcha_page_path(current_customer_id, page),
            **::Captcha::ThrottleRegistry.display_for(match_kind: "template", url_pattern: pattern)
          }
        end
      end

      def update
        page = ::Page.shared.find(params[:id])
        raise ActiveRecord::RecordNotFound unless page.visible_to?("public")

        redirect_for_throttle(::Captcha::Activities::UpdateUrlThrottle.call(
          match_kind: "template",
          url_pattern: "/:customer_id/page/#{page.public_uuid}",
          preset: throttle_params[:preset],
          limit_count: throttle_params[:limit_count],
          period_minutes: throttle_params[:period_minutes],
          page: page,
          skipped: throttle_params[:skipped]
        ))
      end
    end
  end
end
end
end
