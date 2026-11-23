# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  module Captcha
    class SurfacesController < ThrottlesController
      def update
        surface = ::Captcha::SurfaceCatalog.find(params[:surface_key].to_s)
        raise ActiveRecord::RecordNotFound unless surface

        redirect_for_throttle(::Captcha::Activities::UpdateUrlThrottle.call(
          match_kind: "template",
          url_pattern: surface.path,
          preset: throttle_params[:preset],
          limit_count: throttle_params[:limit_count],
          period_minutes: throttle_params[:period_minutes],
          surface_key: surface.key,
          skipped: throttle_params[:skipped]
        ))
      end
    end
  end
end
end
end
