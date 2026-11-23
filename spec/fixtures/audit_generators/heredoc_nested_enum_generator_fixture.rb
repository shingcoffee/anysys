# frozen_string_literal: true

module AuditFixtures
  # Reproduces the shape of the (now removed) TransactionGenerator: a
  # hand-rolled `%w[...].include?` enum check that appears in #generate_body
  # only AFTER a heredoc and a nested block. The audit's Ripper walker has to
  # keep tracking the enclosing method across both constructs to flag it.
  #
  # This used to be asserted against the real generator; that generator was
  # deleted as unreachable dead code, so the shape is preserved here rather
  # than dropping the coverage.
  class HeredocNestedEnumGenerator < CodeGenerators::BaseGenerator
    generator_metadata do
      description "Heredoc + nested block enum fixture"
      category :fixtures
      version "1.0.0"
    end

    def generate_body
      opts = ["isolation: :serializable"]

      inner = <<~RUBY.chomp
        ActiveRecord::Base.transaction(#{opts.join(', ')}) do
          # Child steps execute within this transaction
        end
      RUBY

      [inner].each do
        <<~RUBY
          end
        RUBY
      end

      strategy = config["errorStrategy"]
      strategy = "continue" unless %w[continue fail_track raise].include?(strategy)

      "#{inner}\n# #{strategy}\ntrue"
    end

    def validate_config(_cfg)
      []
    end
  end
end
