# frozen_string_literal: true

# Entity domains are a platform-owner organizing tool. Tenant admins
# browse their entities grouped by domain at /:cid/admin/domains, but
# never see the maintenance domain view or any control that creates,
# edits or moves a domain. Ask this object before rendering those
# controls; HTTP enforcement goes through OwnerOnlySurfaces
# (RouteAuthorization, Ability, grant catalogs).
module EntityDomainVisibility
  module_function

  ROUTE_SUBJECT_PREFIX = "route_admin_maintenance_entity_domain"

  def allowed?(user)
    user.respond_to?(:platform_owner?) && user.platform_owner?
  end

  def controller?(controller_path)
    controller_path.to_s.match?(%r{(?:\A|/)entity_domain})
  end

  def route_subject?(subject)
    subject.to_s.start_with?(ROUTE_SUBJECT_PREFIX)
  end
end
