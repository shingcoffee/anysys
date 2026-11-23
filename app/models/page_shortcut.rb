# frozen_string_literal: true

class PageShortcut < ApplicationRecord
  TARGET_TYPES = %w[WebsitePage Page].freeze

  belongs_to :customer
  belongs_to :target, polymorphic: true, optional: true

  # Explicit tenant scope: routing runs before a request has a Current customer.
  scope :for_customer, ->(customer_id) { where(customer_id: customer_id) }
  scope :by_path, -> { order(:path, :id) }

  # Rails can preload this association for management lists, but neither its
  # loader nor the accessor may constantize an arbitrary persisted/input type.
  def self.polymorphic_class_for(name)
    case name
    when "WebsitePage" then WebsitePage
    when "Page" then Page
    end
  end

  def target
    super if TARGET_TYPES.include?(target_type)
  end
end
