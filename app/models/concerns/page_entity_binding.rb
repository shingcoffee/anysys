# frozen_string_literal: true

# PageEntityBinding
#
# Virtual-attribute and association helpers that bind a Page to its Entity via
# the configuration metadata blob.  All queries are scoped to the page's own
# customer so a stale or forged metadata entity_id cannot reach across tenants.
#
# Provides:
#   #entity          — AR lookup scoped to customer_id
#   #entity_id       — reader delegating into metadata
#   #entity_id=      — writer that also stores entity_name in metadata
#   #entity_out_of_date? — built from an entity version other than the tenant's head
#   .new_with_defaults — factory that stamps a blank page with the canonical config skeleton
#   .default_configuration (private class method) — the canonical blank config hash
#
module PageEntityBinding
  extend ActiveSupport::Concern

  # Get the bound entity from metadata. Scoped to this page's own tenant
  # so a stale/forged metadata entity_id cannot reach across customers.
  def entity
    return nil unless metadata["entity_id"]

    @entity ||= entity_lookup_scope.find_by(id: metadata["entity_id"])
  end

  # Virtual attribute for form binding — reads from configuration metadata.
  def entity_id
    metadata["entity_id"]
  end

  # Set entity_id and update metadata.  Also resolves and caches entity_name
  # so the stored config stays self-describing without extra queries at render time.
  def entity_id=(value)
    config = configuration_json || self.class.send(:default_configuration)
    config["metadata"] ||= {}

    parsed = Integer(value, exception: false) unless value.nil?

    if parsed
      found_entity = entity_lookup_scope.find_by(id: parsed)
      config["metadata"]["entity_id"]   = parsed
      config["metadata"]["entity_name"] = found_entity&.name
    else
      config["metadata"]["entity_id"]   = nil
      config["metadata"]["entity_name"] = nil
    end

    self.configuration_json = config
  end

  # True when the page was generated from an entity version other than the
  # head the current tenant sees. Hand-built pages carry no entity_version_id
  # and are never out of date.
  def entity_out_of_date?(current_version = entity&.resolved_current_version)
    entity_version_id.present? && current_version.present? && entity_version_id != current_version.id
  end

  def entity_lookup_scope
    if shared? || customer_id.nil?
      Entity.shared
    else
      Entity.where(customer_id: customer_id).or(Entity.shared)
    end
  end

  class_methods do
    # Resolves #entity for a whole list in one query instead of one per row,
    # under the same tenant rule as #entity_lookup_scope.
    def preload_entities(pages)
      found = Entity.where(id: pages.filter_map(&:entity_id)).index_by(&:id)
      pages.each do |page|
        entity = found[page.entity_id.to_i]
        next unless entity

        visible = entity.shared? || (!page.shared? && page.customer_id.present? && entity.customer_id == page.customer_id)
        page.instance_variable_set(:@entity, visible ? entity : nil)
      end
      pages
    end

    # Build a new Page pre-populated with the canonical blank configuration.
    def new_with_defaults(attributes = {})
      page = new(attributes)
      page.configuration_json = default_configuration if page.configuration.blank?
      page
    end

    private

    # Canonical blank configuration skeleton.  Every new page starts here so
    # the multi-page structure is established from the first save.
    def default_configuration
      {
        "pages" => [
          {
            "id"     => "page_1",
            "name"   => "Page 1",
            "order"  => 1,
            "fields" => []
          }
        ],
        "metadata" => {
          "entity_id"   => nil,
          "entity_name" => nil,
          "created_at"  => Time.current.iso8601
        }
      }
    end
  end
end
