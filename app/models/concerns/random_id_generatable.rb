# frozen_string_literal: true

# Provides random N-digit integer ID generation for ActiveRecord models.
#
# This concern overrides the default auto-increment ID behavior to generate
# random unique IDs within a specified digit range.
#
# Usage:
#   class Customer < ApplicationRecord
#     include RandomIdGeneratable
#     random_id digits: 8  # generates IDs between 10000000-99999999
#   end
#
module RandomIdGeneratable
  extend ActiveSupport::Concern

  included do
    class_attribute :random_id_digits, default: 8
    class_attribute :random_id_max_attempts, default: 10

    before_create :generate_random_id, unless: :id?
  end

  class_methods do
    # Configure random ID generation
    #
    # @param digits [Integer] Number of digits for the ID (default: 8)
    # @param max_attempts [Integer] Maximum retry attempts on collision (default: 10)
    def random_id(digits: 8, max_attempts: 10)
      self.random_id_digits = digits
      self.random_id_max_attempts = max_attempts
    end

    # Calculate the minimum value for N digits
    def random_id_min
      10**(random_id_digits - 1)
    end

    # Calculate the maximum value for N digits
    def random_id_max
      (10**random_id_digits) - 1
    end

    # Generate a random ID within the configured range
    def generate_unique_random_id
      random_id_max_attempts.times do
        candidate = rand(random_id_min..random_id_max)
        return candidate unless exists?(id: candidate)
      end

      raise "Failed to generate unique ID after #{random_id_max_attempts} attempts"
    end
  end

  private

  def generate_random_id
    self.id = self.class.generate_unique_random_id
  end
end
