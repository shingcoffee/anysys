# frozen_string_literal: true

module AuditFixtures
  class AllowedForbiddenEmissionGenerator < CleanGenerator
    # generator-audit: allow unsafe_marshal -- compatibility payload is trusted and versioned
    def generate_body
      "Marshal.load(payload)"
    end
  end
end
