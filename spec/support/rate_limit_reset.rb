# frozen_string_literal: true

# Authentication::Throttle is process-shared (a MemoryStore fallback in test
# because Rails.cache is NullStore). Without a reset, failed-login POSTs and
# email-flood hits accumulate across unrelated spec files until an innocent
# example trips a cap (order-dependent flake — home_spec was the first
# casualty). Reset before each request example so every spec starts clean.
RSpec.configure do |config|
  config.before(:each, type: :request) do
    Authentication::Throttle.reset_store!
  end
end
