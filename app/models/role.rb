# frozen_string_literal: true

class Role < ApplicationRecord
  belongs_to :customer
  has_many :role_permissions, dependent: :destroy
  has_many :users_roles, dependent: :destroy
  has_many :users, through: :users_roles, class_name: "Authentication::User"

  validates :key,  presence: true, uniqueness: { scope: :customer_id, case_sensitive: false }
  validates :name, presence: true

  scope :system, -> { where(system: true) }
  scope :custom, -> { where(system: false) }

  RESERVED_KEYS = %w[owner admin member].freeze

  def reserved? = RESERVED_KEYS.include?(key)
end
