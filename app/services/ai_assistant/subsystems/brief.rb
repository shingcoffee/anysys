# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # The requirements brief a sub-system build starts from (Operations
    # schema start_subsystem_build.json): the business area, the people who
    # take part, the real-world scenarios and the admin's values.
    class Brief
      SIGNUP = %w[self_signup both].freeze
      STAFF_ACCOUNTS = %w[staff_created both].freeze

      def initialize(raw)
        @raw = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
      end

      def to_h = @raw
      def domain_name = @raw.dig("domain", "name").to_s.squish
      def domain_description = @raw.dig("domain", "description").to_s.strip
      def people = Array(@raw["people"]).grep(Hash)
      def values = Array(@raw["values"]).grep(Hash)
      def not_covered = Array(@raw["not_covered"]).map(&:to_s).reject(&:blank?)

      # How the people the domain serves get their logins: the first
      # non-staff entry that says, else none.
      def sign_in
        people.reject { |row| row["audience"].to_s == EntityAttributeAudience::ADMIN }
              .map { |row| row["sign_in"].presence }.compact.find { |value| value != "none" } || "none"
      end

      def logins? = sign_in != "none"
      def signup? = SIGNUP.include?(sign_in)
      def staff_accounts? = STAFF_ACCOUNTS.include?(sign_in)
    end
  end
end
