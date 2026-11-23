# frozen_string_literal: true

# Journeys are built only by the platform owner; tenant admins and visitors
# run them through the public start URL, which stays outside this gate. Ask
# this object before rendering builder chrome; HTTP enforcement goes through
# OwnerOnlySurfaces (RouteAuthorization, Ability, grant catalogs).
module JourneyVisibility
  module_function

  ROUTE_SUBJECT_PREFIX = "route_admin_maintenance_journey"

  def allowed?(user)
    user.respond_to?(:platform_owner?) && user.platform_owner?
  end

  def controller?(controller_path)
    controller_path.to_s.start_with?("admin/maintenance/journey")
  end

  def route_subject?(subject)
    subject.to_s.start_with?(ROUTE_SUBJECT_PREFIX)
  end
end
