# frozen_string_literal: true

module Roles
  module Contract
    class Update < Reform::Form
      property :name
      property :description

      validates :name, presence: true
    end
  end
end
