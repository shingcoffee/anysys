# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/support/generator_conformance").to_s
require Rails.root.join("spec/support/generator_branch_variants").to_s

# In a multi-tenant application every shared-namespace key must be scoped by
# customer. FlowchartRuntime::Lock already requires a tenant namespace; this
# spec holds every other emitted key, query, and path to the same standard.
#
# Three levels of coverage:
#
#   1. the declared sample input (one config per generator),
#   2. a branch sweep over every reachable emission branch
#      (see spec/support/generator_branch_variants.rb), and
#   3. a per-call-site check that the *key expression itself* carries tenant
#      identity, not merely the surrounding body.
#
# Level 2 exists because level 1 alone demonstrably missed real leaks: an
# unscoped `Rails.cache.fetch("rate:#{from}:#{to}")` in `currency_convert`
# lived on the `rateSource == "external"` branch, which the sample input never
# selected, and a `File.open` on a raw config-supplied path in `log` lived on
# the `logger == "file"` branch, which the sample also never selected.
#
# Level 3 exists because "the body mentions customer_id somewhere" is a weak
# proxy — a generator can scope one key correctly and leak another in the same
# body.
RSpec.describe "generated activity tenant scoping" do
  SHARED_NAMESPACE_PATTERNS = {
    "Rails.cache" => /Rails\.cache\.(read|write|delete|fetch|exist\?|increment|decrement)/,
    "filesystem"  => /File\.(open|write|read|delete)|FileUtils\./
  }.freeze

  TENANT_MARKERS = /
    customer_id | tenant_namespace | FlowchartRuntime::CacheKey |
    FlowchartRuntime::SandboxPath | FlowchartRuntime::LogFile | Current\.customer
  /x

  # Call sites whose FIRST argument is the shared-namespace key or path.
  KEYED_CALL_SITE = /
    (?:Rails\.cache\.(?:read|write|delete|fetch|exist\?|increment|decrement) |
       File\.(?:open|write|read|delete) |
       FileUtils\.\w+)
    \(
  /x

  LOCAL_VARIABLE = /\A[a-z_][a-z0-9_]*\z/

  def offending_namespaces(body)
    SHARED_NAMESPACE_PATTERNS.select { |_name, pattern| body.match?(pattern) }.keys
  end

  # Consumes from +index+ (just past an opening paren) until the matching close
  # paren or a top-level comma, honoring nesting and string literals. Returns
  # the first argument source.
  def first_argument(body, index)
    depth = 0
    quote = nil
    buffer = +""
    while index < body.length
      char = body[index]
      if quote
        quote = nil if char == quote && body[index - 1] != "\\"
      elsif ['"', "'"].include?(char)
        quote = char
      elsif "([{".include?(char)
        depth += 1
      elsif ")]}".include?(char)
        break if depth.zero?

        depth -= 1
      elsif char == "," && depth.zero?
        break
      end
      buffer << char
      index += 1
    end
    buffer.strip
  end

  # Every statement in +body+ that assigns +name+, so a key built up over
  # several lines (or reassigned) is evaluated as a whole.
  def assignments(body, name)
    pattern = /^[ \t]*#{Regexp.escape(name)}\s*=(?!=)/
    statements = []
    cursor = 0
    while (start = body.index(pattern, cursor))
      statement = statement_at(body, start)
      statements << statement
      cursor = start + [statement.length, 1].max
    end
    statements
  end

  # The full statement beginning at +start+: extends past newlines while any
  # bracket is still open.
  def statement_at(body, start)
    depth = 0
    quote = nil
    index = start
    while index < body.length
      char = body[index]
      if quote
        quote = nil if char == quote && body[index - 1] != "\\"
      elsif ['"', "'"].include?(char)
        quote = char
      elsif "([{".include?(char)
        depth += 1
      elsif ")]}".include?(char)
        depth -= 1
      elsif char == "\n" && depth <= 0
        break
      end
      index += 1
    end
    body[start...index]
  end

  # The key/path expression of every shared-namespace call site in +body+,
  # resolved through local-variable assignments.
  def key_expressions(body)
    cursor = 0
    found = []
    while (match = KEYED_CALL_SITE.match(body, cursor))
      cursor = match.end(0)
      expression = first_argument(body, match.end(0))
      if expression.match?(LOCAL_VARIABLE)
        resolved = assignments(body, expression)
        expression = resolved.join("\n") unless resolved.empty?
      end
      found << expression
    end
    found
  end

  def assert_scoped(body, label)
    offending = offending_namespaces(body)
    return if offending.empty?

    expect(body).to match(TENANT_MARKERS),
      "#{label} emits #{offending.join(', ')} access with no customer scoping:\n#{body}"

    key_expressions(body).each do |expression|
      expect(expression).to match(TENANT_MARKERS),
        "#{label} builds a shared-namespace key with no tenant identity:\n" \
        "  #{expression}\nfull body:\n#{body}"
    end
  end

  # The guard is only worth its runtime if it actually fails on a leak. These
  # examples pin the two detection paths against synthetic bodies.
  describe "harness self-check" do
    it "accepts an inline tenant-scoped key" do
      body = %(Rails.cache.write(FlowchartRuntime::CacheKey.scoped(ctx[:customer_id], "k"), 1)\ntrue)
      expect { assert_scoped(body, "synthetic") }.not_to raise_error
    end

    it "rejects an inline unscoped key" do
      body = %(Rails.cache.fetch("rate:\#{_from}:\#{_to}") { 1 }\ntrue)
      expect { assert_scoped(body, "synthetic") }
        .to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "resolves a key held in a local variable" do
      body = <<~RUBY
        _k = FlowchartRuntime::CacheKey.scoped(
          ctx[:customer_id],
          "thing"
        )
        Rails.cache.read(_k)
      RUBY
      expect(key_expressions(body).first).to include("ctx[:customer_id]")
    end

    it "rejects an unscoped local key even when the body mentions customer_id elsewhere" do
      body = <<~RUBY
        _audit = { customer_id: ctx[:customer_id] }
        _k = "rate:usd"
        Rails.cache.read(_k)
      RUBY
      expect { assert_scoped(body, "synthetic") }
        .to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "keeps a string literal containing a comma intact" do
      body = %(Rails.cache.write("a,b", 1))
      expect(key_expressions(body)).to eq(['"a,b"'])
    end

    it "reports no call sites for a body with none" do
      expect(key_expressions("true")).to be_empty
    end
  end

  CodeGenerators::GeneratorRegistry.step_action_generators.each do |action_key, generator_class|
    it "scopes any shared-namespace access by customer in #{action_key}" do
      body = GeneratorConformance.emit(generator_class, generator_class.sample_input).to_s
      next if body.empty?

      assert_scoped(body, action_key)
    end

    it "scopes shared-namespace access on every reachable branch of #{action_key}" do
      expect(GeneratorBranchVariants.truncated?(generator_class, action_key)).to be(false),
        "#{action_key} has more configurations than " \
        "GeneratorBranchVariants::MAX_VARIANTS_PER_GENERATOR allows; raise the cap rather " \
        "than sweeping a subset"

      variants = GeneratorBranchVariants.variants(generator_class, action_key)
      expect(variants).not_to be_empty

      aggregate_failures do
        variants.each do |variant|
          next if GeneratorConformance.validation_errors(generator_class, variant.config).any?

          body = GeneratorConformance.emit(generator_class, variant.config).to_s
          next if body.empty?

          assert_scoped(body, "#{action_key} [#{variant.label}]")
        end
      end
    end
  end
end
