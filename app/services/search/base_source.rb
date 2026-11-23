# frozen_string_literal: true

module Search
  class BaseSource
    MAX_PER_GROUP = 5
    MIN_QUERY_LENGTH = 2

    def initialize(customer:, query:, user:)
      @customer = customer
      @query    = query.to_s.strip
      @user     = user
    end

    def to_group
      { key: group_key, label: group_label, items: usable_query? ? items : [] }
    end

    protected

    attr_reader :customer, :query, :user

    def usable_query?
      query.length >= MIN_QUERY_LENGTH
    end

    def escaped_like
      ActiveRecord::Base.sanitize_sql_like(query)
    end

    def group_key   = raise NotImplementedError
    def group_label = raise NotImplementedError
    def items       = raise NotImplementedError
  end
end
