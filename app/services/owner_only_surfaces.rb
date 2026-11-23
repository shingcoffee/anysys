# frozen_string_literal: true

# Tenant-path controllers only the platform owner may reach. Each entry
# answers `controller?(controller_path)` and `route_subject?(subject)`.
# RouteAuthorization, Ability and the grant catalogs ask this module so a new
# owner-only surface is registered once.
module OwnerOnlySurfaces
  module_function

  def surfaces = [FlowchartVisibility, EntityDomainVisibility, JourneyVisibility]

  def controller?(controller_path)
    surfaces.any? { |surface| surface.controller?(controller_path) }
  end

  def route_subject?(subject)
    surfaces.any? { |surface| surface.route_subject?(subject) }
  end
end
