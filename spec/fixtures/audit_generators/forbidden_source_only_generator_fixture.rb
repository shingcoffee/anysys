# frozen_string_literal: true

module AuditFixtures
  class ForbiddenSourceOnlyGenerator < CleanGenerator
    EXAMPLE = "Marshal.load is forbidden in emitted code"

    # Marshal.load in a generator-source comment is not emitted.
    def generate_body
      "true"
    end
  end
end
