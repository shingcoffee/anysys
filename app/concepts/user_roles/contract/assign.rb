# frozen_string_literal: true

module UserRoles
  module Contract
    class Assign < Reform::Form
      property :role_ids, virtual: true

      validates :role_ids, presence: true, allow_blank: true
    end
  end
end
