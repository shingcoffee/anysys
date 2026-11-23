# frozen_string_literal: true

class SidebarContributor
  def initialize(context)
    @context = context
  end

  # @return [Array<SidebarNode>] top-level nodes for this contributor
  def contribute
    raise NotImplementedError, "#{self.class} must implement #contribute"
  end

  def self.registry
    [
      EntitiesContributor,
      ModulesContributor,
      SettingsContributor,
      MaintenanceContributor
    ]
  end

  private

  attr_reader :context
  def customer    = context.current_customer
  def customer_id = context.customer_id
  def current_user = context.current_user
end
