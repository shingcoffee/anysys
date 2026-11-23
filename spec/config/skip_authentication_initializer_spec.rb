# frozen_string_literal: true

require "rails_helper"

# The skip_authentication.rb initializer disables auth in development.
# It must hard-fail rather than silently activate if loaded in any other env,
# and must require an explicit opt-in env var even in development.
RSpec.describe "config/initializers/skip_authentication.rb" do
  let(:source) { File.read(Rails.root.join("config/initializers/skip_authentication.rb")) }

  it "requires an explicit env var to take effect" do
    expect(source).to match(/ENV\[\s*["']SKIP_AUTH["']\s*\]/)
  end

  it "raises a hard error if invoked outside development" do
    expect(source).to match(/raise/i)
    expect(source).to match(/Rails\.env\.development\?/)
  end
end
