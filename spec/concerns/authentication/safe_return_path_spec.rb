# frozen_string_literal: true

require "rails_helper"

# Allow-list for Devise's `stored_location_for(:user)`. The stored value is
# attacker-influenced (it is whatever path the browser was bounced from), so
# anything that escapes the user's own tenant is an open-redirect off the back
# of a successful sign-in.
RSpec.describe Authentication::SafeReturnPath do
  subject(:host) { host_class.new }

  let(:host_class) do
    Class.new do
      include Authentication::SafeReturnPath

      # The concern's helpers are private by design; expose them for the unit.
      public :safe_return_path_for, :peek_return_to, :restore_return_to

      def session
        @session ||= {}
      end
    end
  end

  let(:user) { instance_double(Authentication::User, customer_id: 12_345_678) }

  describe "#safe_return_path_for" do
    it "accepts a path inside the user's own tenant" do
      expect(host.safe_return_path_for(user, "/12345678/admin/dashboard"))
        .to eq("/12345678/admin/dashboard")
    end

    it "accepts the public OAuth authorize path" do
      expect(host.safe_return_path_for(user, "/oauth/authorize")).to eq("/oauth/authorize")
      expect(host.safe_return_path_for(user, "/oauth/authorize?client_id=x"))
        .to eq("/oauth/authorize?client_id=x")
    end

    it "rejects another tenant's path" do
      expect(host.safe_return_path_for(user, "/87654321/admin/dashboard")).to be_nil
    end

    it "rejects an absolute off-site URL" do
      expect(host.safe_return_path_for(user, "https://evil.example/steal")).to be_nil
    end

    it "rejects a protocol-relative URL" do
      expect(host.safe_return_path_for(user, "//evil.example/steal")).to be_nil
    end

    it "rejects a backslash-escaped protocol-relative URL" do
      expect(host.safe_return_path_for(user, "/\\evil.example/steal")).to be_nil
    end

    # Browsers strip C0 control characters before resolving a URL, so each of
    # these normalises to "//evil.example" — a protocol-relative off-site
    # redirect that the plain start_with?("//") check does not catch.
    it "rejects a control character smuggled ahead of a protocol-relative URL" do
      [ "\t", "\n", "\r", "\u0000", "\u000B", "\u000C", "\u001F", "\u007F" ].each do |char|
        expect(host.safe_return_path_for(user, "/#{char}/evil.example"))
          .to be_nil, "expected #{char.inspect} to be rejected"
      end
    end

    it "rejects a control character anywhere in an otherwise same-tenant path" do
      expect(host.safe_return_path_for(user, "/12345678/admin\n/dashboard")).to be_nil
    end

    # Space is percent-encoded in a real request path and is not a
    # normalisation vector, so it must not be treated as a control character.
    it "does not reject a same-tenant path over its query string" do
      expect(host.safe_return_path_for(user, "/12345678/admin/users?q=a%20b"))
        .to eq("/12345678/admin/users?q=a%20b")
    end

    it "rejects a non-path value" do
      expect(host.safe_return_path_for(user, "admin/dashboard")).to be_nil
      expect(host.safe_return_path_for(user, nil)).to be_nil
      expect(host.safe_return_path_for(user, 42)).to be_nil
    end

    it "rejects a tenant path when there is no user to scope it against" do
      expect(host.safe_return_path_for(nil, "/12345678/admin/dashboard")).to be_nil
    end

    it "still accepts the OAuth authorize path with no user" do
      expect(host.safe_return_path_for(nil, "/oauth/authorize")).to eq("/oauth/authorize")
    end

    # A tenant prefix must match a whole segment, or "/123456789/..." (a
    # different customer whose id merely starts with the same digits) would
    # pass as same-tenant.
    it "rejects a tenant id that only shares a prefix" do
      expect(host.safe_return_path_for(user, "/123456789/admin/dashboard")).to be_nil
    end
  end

  describe "return-to round trip" do
    it "peeks the stored location without consuming it" do
      host.session["user_return_to"] = "/12345678/admin/dashboard"
      expect(host.peek_return_to).to eq("/12345678/admin/dashboard")
      expect(host.session["user_return_to"]).to eq("/12345678/admin/dashboard")
    end

    it "restores a path" do
      host.restore_return_to("/12345678/admin/dashboard")
      expect(host.session["user_return_to"]).to eq("/12345678/admin/dashboard")
    end

    it "does not store a blank path" do
      host.restore_return_to(nil)
      host.restore_return_to("")
      expect(host.session).to be_empty
    end
  end
end
