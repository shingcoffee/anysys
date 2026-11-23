# frozen_string_literal: true

module AuditFixtures
  class SelfAuthorizingGeneratedGenerator < CleanGenerator
    DIRECTIVE = "# generator-audit: allow unsafe_marshal -- generated code cannot authorize itself"

    def generate_body
      <<~RUBY
        #{DIRECTIVE}
        Marshal.load(payload)
      RUBY
    end
  end
end
