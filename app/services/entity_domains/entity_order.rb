# frozen_string_literal: true

module EntityDomains
  # Lists a domain's entities primary first: an entity that declares
  # associations to other entities is primary and leads, the one declaring
  # the most first; the rest follow. Labels, then ids, only break ties. The
  # Domains sidebar and the domain page's default card order share it.
  module EntityOrder
    module_function

    def sort(entities) = Array(entities).sort_by { |entity| key(entity) }

    def key(entity) = [-entity.associations_list.size, entity.display_label.to_s.downcase, entity.id.to_i]

    def primary?(entity) = entity.associations_list.any?
  end
end
