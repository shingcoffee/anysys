# frozen_string_literal: true

class SearchQuery
  SOURCES = [
    Search::PagesSource,
    Search::EntitiesSource,
    Search::ModulesSource
  ].freeze

  def self.call(customer:, query:, user:)
    SOURCES
      .map { |src| src.new(customer: customer, query: query, user: user).to_group }
      .reject { |g| g[:items].empty? }
  end
end
