# frozen_string_literal: true

require "rails_helper"

RSpec.describe "retired email admin URLs", type: :request do
  it_behaves_like "a retired email admin URL", from: "engagement", to: "health"
  it_behaves_like "a retired email admin URL", from: "deliverability", to: "health"
  it_behaves_like "a retired email admin URL", from: "reports", to: "dashboard"
end
