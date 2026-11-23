# frozen_string_literal: true

module InvocationHelpers
  def stash_invocation(session:, customer:, module_key: "test_module", input: { x: 1 }, exit_target: nil)
    session[:feature_module_invocation] = {
      module_key:  module_key,
      customer_id: customer.id,
      input:       input,
      exit_target: exit_target,
      started_at:  Time.current.iso8601
    }
  end
end

RSpec.configure do |c|
  c.include InvocationHelpers, type: :request
end
