# frozen_string_literal: true

# Shared contexts that replace the ~200x repeated auth/tenant boilerplate
# (`let(:customer) { create(:customer) }` + `create(:user, :role)` + `sign_in`).
#
# Usage:
#   include_context "as admin"           # => customer, admin (signed in)
#   include_context "as member"          # => customer, member (signed in)
#   include_context "as platform owner"  # => customer (platform), owner (signed in)
#   include_context "admin records"      # => customer, admin (no sign-in; mixed-auth files)
#   include_context "member records"     # => customer, member (no sign-in)
#
# `sign_in` is only available in request/system/controller specs (Devise test
# helpers). In other spec types the contexts still expose the records but skip
# sign-in.
RSpec.shared_context "admin records" do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }
end

RSpec.shared_context "member records" do
  let(:customer) { create(:customer) }
  let(:member)   { create(:user, :member, customer: customer) }
end

RSpec.shared_context "as admin" do
  include_context "admin records"

  before { sign_in admin if respond_to?(:sign_in) }
end

RSpec.shared_context "as member" do
  include_context "member records"

  before { sign_in member if respond_to?(:sign_in) }
end

RSpec.shared_context "as platform owner" do
  let(:owner)    { find_or_create_platform_owner }
  let(:customer) { owner.customer }

  before { sign_in owner if respond_to?(:sign_in) }
end

# Tenant customer + admin record, but the signed-in actor is the platform
# owner (cross-tenant). Use for flowchart CUD, which is owner-only.
RSpec.shared_context "as platform owner on tenant" do
  include_context "admin records"
  let(:platform_owner) { find_or_create_platform_owner }

  before { sign_in platform_owner if respond_to?(:sign_in) }
end
