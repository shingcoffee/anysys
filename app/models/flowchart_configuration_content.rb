# frozen_string_literal: true

# Content-addressed store for Flowchart configuration snapshots. See ContentAddressable.
class FlowchartConfigurationContent < ApplicationRecord
  include ContentAddressable

  has_many :flowchart_versions, foreign_key: :content_id, inverse_of: :content,
                                dependent: :restrict_with_exception

  def self.version_association = :flowchart_versions
end
