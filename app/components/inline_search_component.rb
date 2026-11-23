# frozen_string_literal: true

class InlineSearchComponent < ApplicationComponent
  def initialize(customer_id:, mobile: false)
    @customer_id = customer_id
    @mobile = mobile
  end

  attr_reader :customer_id

  def mobile?
    @mobile
  end
end
