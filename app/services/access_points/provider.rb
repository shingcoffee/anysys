# frozen_string_literal: true

module AccessPoints
  # Abstract base. Subclasses contribute a slice of the access-point catalog.
  class Provider
    # @param customer_id [Integer]
    # @return [Array<AccessPoints::Descriptor>]
    def call(customer_id:) = raise NotImplementedError, "#{self.class}#call"

    def group_key   = raise NotImplementedError
    def group_label = raise NotImplementedError

    # Catalog group headers use descriptor.group_key, which may be more
    # specific than #group_key (e.g. modules.payments vs modules). Override
    # when those derived keys need their own labels.
    def label_for_group(key)
      group_label if key.to_s == group_key.to_s
    end

    def applicable?(customer_id:) = true
  end
end
