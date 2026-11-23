# frozen_string_literal: true

class UsersRole < ApplicationRecord
  self.table_name = "users_roles"

  belongs_to :user, class_name: "Authentication::User"
  belongs_to :role

  validates :user_id, uniqueness: { scope: :role_id }
  set_callback :validation, :around, :serialize_assignment
  validate :validate_assignment_policy
  before_destroy :protect_reserved_assignment

  private

  def serialize_assignment(&block)
    UserRoles::AssignmentPolicy.serialize(self, &block)
  end

  def validate_assignment_policy
    UserRoles::AssignmentPolicy.validate(self)
  end

  def protect_reserved_assignment
    UserRoles::AssignmentPolicy.serialize(self) do
      throw :abort unless UserRoles::AssignmentPolicy.removable?(self)
    end
  end
end
