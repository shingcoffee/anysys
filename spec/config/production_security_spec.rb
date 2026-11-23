# frozen_string_literal: true

require "rails_helper"

# These specs lock in security-sensitive flags in config/environments/production.rb.
# We avoid booting the production environment by reading the file as source.
RSpec.describe "production environment config" do
  let(:source) { File.read(Rails.root.join("config/environments/production.rb")) }

  it "enables force_ssl so cookies are Secure and HSTS is sent" do
    expect(source).to match(/^\s*config\.force_ssl\s*=\s*true/)
  end

  it "enables assume_ssl so the app trusts an SSL-terminating proxy" do
    expect(source).to match(/^\s*config\.assume_ssl\s*=\s*true/)
  end
end
