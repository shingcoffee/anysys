# frozen_string_literal: true

# Breadcrumbs for Constants / Entities / Flowcharts / Pages.
#
# Tenant maintenance and platform Shared Resources remount the same controllers
# and views. Named path helpers rewrite under Current.shared_resources_mode, so
# this list is the single crumb trail for both URL prefixes.
module DefinitionResourceHelper
  INDEX_PATH = {
    constants:  :admin_maintenance_constants_path,
    entities:   :admin_maintenance_entities_path,
    flowcharts: :admin_maintenance_flowcharts_path,
    pages:      :admin_maintenance_pages_path
  }.freeze

  def definition_resource_breadcrumbs(resource, *trail)
    resource   = resource.to_sym
    index_path = public_send(INDEX_PATH.fetch(resource), current_customer_id)

    crumbs = [
      { label: t("maint_core.nav.maintenance"), path: admin_maintenance_path(current_customer_id) },
      { label: t("maint_core.nav.#{resource}"), path: trail.any? ? index_path : nil }
    ]
    trail.each { |item| crumbs << (item.is_a?(Hash) ? item : { label: item }) }
    crumbs
  end

  # Reset-to-default action for a tenant override of a shared resource, or nil.
  def definition_override_reset_action(record)
    return unless record.shared? && !shared_resources_mode? && record.customer_override?(current_customer_id)

    {
      label: t("maint_core.entities.show.reset_to_default"),
      path: public_send(
        "admin_maintenance_#{record.model_name.singular}_override_path",
        current_customer_id,
        record
      ),
      variant: :secondary,
      data: {
        turbo_method: :delete,
        turbo_confirm: t("maint_core.entities.show.reset_override_confirm")
      }
    }
  end
end
