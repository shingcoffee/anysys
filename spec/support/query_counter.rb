# frozen_string_literal: true

# Count SQL statements inside a block, ignoring schema/transaction noise.
# Used by N+1 regression examples that compare a warm run against a grown dataset.
module QueryCounter
  IGNORED_SQL_NAMES = %w[SCHEMA TRANSACTION].freeze

  def count_queries
    count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      count += 1 unless IGNORED_SQL_NAMES.include?(payload[:name].to_s)
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end

RSpec.configure do |config|
  config.include QueryCounter
end
