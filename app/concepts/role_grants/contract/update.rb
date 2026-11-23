# frozen_string_literal: true

module RoleGrants
  module Contract
    class Update < Reform::Form
      property :added,   virtual: true
      property :removed, virtual: true

      validates :added,   presence: true, allow_blank: true
      validates :removed, presence: true, allow_blank: true
    end
  end
end
