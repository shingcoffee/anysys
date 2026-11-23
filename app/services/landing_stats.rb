# frozen_string_literal: true

class LandingStats
  def self.for(customer) = new(customer)

  def initialize(customer)
    @customer = customer
  end

  def to_h
    {
      entities: Entity.for_customer(cid).non_bridge.count,
      pages: page_counts,
      modules_enabled: FeatureModules::CustomerAssignment.where(customer_id: cid, status: :active).count,
      users: Authentication::User.where(customer_id: cid, status: :active).count
    }
  end

  private

  def page_counts
    total = Page.for_customer(cid).count
    launched = Page.for_customer(cid).where(launched: true).count
    { total: total, launched: launched, draft: total - launched }
  end

  def cid = @customer.id
end
