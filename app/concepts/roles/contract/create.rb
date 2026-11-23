# frozen_string_literal: true

module Roles
  module Contract
    class Create < Reform::Form
      property :key
      property :name
      property :description

      validates :key,  presence: true, format: { with: /\A[a-z0-9_]+\z/ }
      validates :name, presence: true
    end
  end
end
