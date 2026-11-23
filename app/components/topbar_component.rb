# frozen_string_literal: true

class TopbarComponent < ApplicationComponent
  def initialize(customer:, user:)
    @customer = customer
    @user = user
  end

  attr_reader :customer, :user
end
