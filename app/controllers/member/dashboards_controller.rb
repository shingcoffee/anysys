# frozen_string_literal: true

module Member
  class DashboardsController < BaseController
    def show
      @greeting       = greeting_for(Time.zone.now)
      @recent_signins = recent_signins
      @payments_enabled = FeatureModules::Module.enabled?(
        key: "payment", customer_id: current_user.customer_id
      )
    end

    private

    def greeting_for(time)
      case time.hour
      when 5..11  then t("member.dashboards.show.greeting_morning")
      when 12..17 then t("member.dashboards.show.greeting_afternoon")
      else             t("member.dashboards.show.greeting_evening")
      end
    end

    def recent_signins
      [
        { at: current_user.last_sign_in_at, ip: current_user.last_sign_in_ip },
        { at: current_user.current_sign_in_at, ip: current_user.current_sign_in_ip }
      ].select { |row| row[:at].present? }.uniq.first(5)
    end
  end
end
