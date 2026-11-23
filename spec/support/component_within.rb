# frozen_string_literal: true

# Component specs do not include Capybara::DSL, so a bare `within(...) { }`
# resolves to an RSpec matcher and silently discards its block. This scopes
# `page` to the matched node for the duration of the block instead.
module ComponentWithin
  include ViewComponent::TestHelpers

  def within(*args, **options)
    scope = page.find(*args, **options)
    previous, @component_within_scope = @component_within_scope, scope
    yield
  ensure
    @component_within_scope = previous
  end

  def page
    @component_within_scope || super
  end
end

RSpec.configure do |config|
  config.include ComponentWithin, type: :component
end
