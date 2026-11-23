# frozen_string_literal: true

# Isolated Rails.env stubs. Pair with ClimateControl when the code also reads ENV.
module RailsEnvHelpers
  def with_rails_env(name)
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(name.to_s))
    yield
  end
end

RSpec.configure do |config|
  config.include RailsEnvHelpers
end
