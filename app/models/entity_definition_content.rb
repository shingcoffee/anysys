# frozen_string_literal: true

# Content-addressed store for Entity definition snapshots. See ContentAddressable.
class EntityDefinitionContent < ApplicationRecord
  include ContentAddressable

  has_many :entity_versions, foreign_key: :content_id, inverse_of: :content,
                             dependent: :restrict_with_exception

  def self.version_association = :entity_versions
end
