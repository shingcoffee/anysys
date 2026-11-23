# frozen_string_literal: true

# Content-addressed store for Page configuration snapshots. See ContentAddressable.
class PageConfigurationContent < ApplicationRecord
  include ContentAddressable

  has_many :page_versions, foreign_key: :content_id, inverse_of: :content,
                           dependent: :restrict_with_exception

  def self.version_association = :page_versions
end
