# frozen_string_literal: true

module Entities
  # Top-left card on the entity detail show surface — mirrors the pages
  # Distribution / flowchart Lifecycle pattern with the entity's primary
  # operational action (open Entries).
  class AccessCardComponent < ViewComponent::Base
    def initialize(entity:, customer_id:)
      @entity      = entity
      @customer_id = customer_id
    end

    def entries_path
      helpers.admin_entity_path(customer_id, entity)
    end

    def entries_count
      @entries_count ||= EntityEntry.where(customer_id: customer_id, entity_id: entity.id).count
    end

    private

    attr_reader :entity, :customer_id
  end
end
