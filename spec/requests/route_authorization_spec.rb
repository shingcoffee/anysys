# frozen_string_literal: true

require "rails_helper"

# Verifies the controller-side guarantees of RouteAuthorization:
#   - admin and member routes fail closed for anonymous traffic
#   - the platform namespace is restricted to platform-owner users
#   - role gates: admin/owner for /admin/*, member for /member/*
#   - access-denied responses keep the user inside their tenant
RSpec.describe "RouteAuthorization", type: :request do
  let_it_be(:customer) { create(:customer) }

  describe "anonymous access to a protected route" do
    it "is rejected for /admin/* (302/401), never silently allowed" do
      get "/#{customer.id}/admin/dashboard"
      expect([302, 401]).to include(response.status)
      expect(response.status).not_to eq(200)
    end
  end

  describe "path detection" do
    it "recognises /:cid/admin/* as protected" do
      expect("/12345678/admin/dashboard").to match(RouteAuthorization::ADMIN_PATH_PATTERN)
    end

    it "recognises /:cid/member/* as protected" do
      expect("/12345678/member/forms/x").to match(RouteAuthorization::MEMBER_PATH_PATTERN)
    end

    it "does not classify arbitrary tenant paths as admin or member" do
      expect("/12345678/page/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee").not_to match(RouteAuthorization::ADMIN_PATH_PATTERN)
      expect("/12345678/page/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee").not_to match(RouteAuthorization::MEMBER_PATH_PATTERN)
    end

    # `admin_root` and `member_dashboard` are routed as `/:customer_id/admin(.:format)`
    # and `/:customer_id/member(.:format)`. A boundary of `/|\z` matched neither
    # `/12345678/admin.json` nor the bare `/12345678/admin`, and every filter in
    # the concern is declared `if: :route_protection_required?` — so those two
    # namespace roots answered with no authentication, no role gate, and no
    # CanCan check at all.
    it "classifies the bare namespace roots as protected" do
      expect("/12345678/admin").to match(RouteAuthorization::ADMIN_PATH_PATTERN)
      expect("/12345678/member").to match(RouteAuthorization::MEMBER_PATH_PATTERN)
    end

    it "classifies a format-suffixed namespace root as protected" do
      expect("/12345678/admin.json").to match(RouteAuthorization::ADMIN_PATH_PATTERN)
      expect("/12345678/admin.html").to match(RouteAuthorization::ADMIN_PATH_PATTERN)
      expect("/12345678/member.json").to match(RouteAuthorization::MEMBER_PATH_PATTERN)
    end

    # The boundary must not widen into a prefix match, or an unrelated public
    # path that merely starts with the same letters would be swept in.
    it "does not classify a path that only shares the namespace prefix" do
      expect("/12345678/administrators").not_to match(RouteAuthorization::ADMIN_PATH_PATTERN)
      expect("/12345678/memberships").not_to match(RouteAuthorization::MEMBER_PATH_PATTERN)
    end
  end

  # The bypass above was reachable over HTTP, not just in the regex, so prove
  # it at the request layer too.
  describe "namespace-root access" do
    it "rejects anonymous traffic to the bare admin root" do
      get "/#{customer.id}/admin"
      expect([ 302, 401 ]).to include(response.status)
      expect(response.status).not_to eq(200)
    end

    it "rejects anonymous traffic to the format-suffixed admin root" do
      get "/#{customer.id}/admin.json"
      expect(response.status).not_to eq(200)
    end

    it "rejects anonymous traffic to the bare member root" do
      get "/#{customer.id}/member"
      expect([ 302, 401 ]).to include(response.status)
      expect(response.status).not_to eq(200)
    end

    it "rejects a member-role user at the format-suffixed admin root" do
      sign_in create(:user, :member, customer: customer)

      get "/#{customer.id}/admin.json"
      expect(response.status).not_to eq(200)
    end
  end

  # `request.path` prepends SCRIPT_NAME. Categorising on it meant that mounting
  # the app under a sub-path (RAILS_RELATIVE_URL_ROOT, or a proxy setting
  # SCRIPT_NAME) kept routing intact while un-matching every pattern here — a
  # total bypass of the concern. `request.path_info` is the string the router
  # itself matched.
  describe "SCRIPT_NAME independence" do
    it "still protects /admin/* when the app is mounted under a sub-path" do
      get "/#{customer.id}/admin/dashboard", env: { "SCRIPT_NAME" => "/anysys" }
      # Warden may replace PATH_INFO with its failure-app path after the 302;
      # SCRIPT_NAME is what proves the mount prefix was applied.
      expect(request.script_name).to eq("/anysys")
      expect([ 302, 401 ]).to include(response.status)
      expect(response.status).not_to eq(200)
    end
  end

  describe "SCRIPT_NAME tenant isolation" do
    it "still rejects a same-role admin using another tenant's URL when mounted under a sub-path" do
      admin = create(:user, :admin, customer: customer)
      other = create(:customer)
      sign_in admin

      get "/#{other.id}/admin/dashboard", env: { "SCRIPT_NAME" => "/anysys" }

      expect(request.path).to eq("/anysys/#{other.id}/admin/dashboard")
      expect(request.path_info).to eq("/#{other.id}/admin/dashboard")
      expect(response.status).not_to eq(200)
      expect(response.status).not_to eq(500)
    end
  end

  describe "former flowchart catch-all paths" do
    it "are not routed" do
      get "/#{customer.id}/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee/1"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "flowchart path detection" do
    it "recognises tenant flowchart paths" do
      expect("/12345678/admin/maintenance/flowcharts").to match(RouteAuthorization::FLOWCHART_PATH_PATTERN)
      expect("/12345678/admin/maintenance/flowcharts/1/edit").to match(RouteAuthorization::FLOWCHART_PATH_PATTERN)
      expect("/12345678/admin/maintenance/flowcharts.json").to match(RouteAuthorization::FLOWCHART_PATH_PATTERN)
      expect("/12345678/admin/maintenance/flowcharts/1/copy").to match(RouteAuthorization::FLOWCHART_PATH_PATTERN)
    end

    it "does not classify neighboring maintenance resources as flowcharts" do
      expect("/12345678/admin/maintenance/pages").not_to match(RouteAuthorization::FLOWCHART_PATH_PATTERN)
      expect("/12345678/admin/maintenance/entities").not_to match(RouteAuthorization::FLOWCHART_PATH_PATTERN)
      expect("/12345678/admin/maintenance/flowchartses").not_to match(RouteAuthorization::FLOWCHART_PATH_PATTERN)
    end
  end

  describe "flowchart namespace restriction" do
    it "denies a tenant admin reaching /admin/maintenance/flowcharts" do
      sign_in create(:user, :admin, customer: customer)
      get "/#{customer.id}/admin/maintenance/flowcharts"
      expect([302, 403]).to include(response.status)
      expect(response.status).not_to eq(200)
    end

    it "denies a tenant admin JSON index of flowcharts" do
      sign_in create(:user, :admin, customer: customer)
      get "/#{customer.id}/admin/maintenance/flowcharts", headers: { "Accept" => "application/json" }
      expect(response.status).not_to eq(200)
    end

    it "allows the platform owner on a tenant flowchart path" do
      sign_in find_or_create_platform_owner
      get "/#{customer.id}/admin/maintenance/flowcharts"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "platform namespace restriction" do
    let(:non_platform_owner) { create(:user, customer: customer, role: :admin) }

    before { sign_in non_platform_owner }

    it "denies a non-platform owner reaching admin/maintenance/platform/*" do
      # An owner under a normal customer is :manage, :all in the Ability,
      # but the platform namespace is gated by a separate path check that
      # must override owner privilege.
      get "/#{customer.id}/admin/maintenance/platform/constants"
      expect([302, 403, 404]).to include(response.status)
      expect(response.status).not_to eq(200)
    end
  end

  describe "admin role gate" do
    let(:member) { create(:user, customer: customer) }

    before { sign_in member }

    it "denies a member-role user reaching /admin/*" do
      get "/#{customer.id}/admin/dashboard"
      expect([302, 403]).to include(response.status)
      expect(response.status).not_to eq(200)
    end
  end

  describe "access-denied redirect target" do
    let(:member) { create(:user, customer: customer) }

    before { sign_in member }

    it "redirects HTML denials to a tenant-scoped path, not the marketing root" do
      get "/#{customer.id}/admin/maintenance/flowcharts"
      if response.status == 302
        expect(response.location).to include("/#{customer.id}")
      end
    end

    it "renders JSON denials with a forbidden status" do
      get "/#{customer.id}/admin/maintenance/flowcharts", headers: { "Accept" => "application/json" }
      expect([302, 403]).to include(response.status)
    end
  end

  # -------------------------------------------------------------------------
  # allow_admin_member_preview! write-gate invariant
  #
  # The opt-in permits same-tenant admin/owner to GET/HEAD a member-namespace
  # controller; it must never let admin pass write verbs (POST/PATCH/PUT/DELETE).
  # We prove this by temporarily opting Member::ProfilesController in
  # (PATCH /:cid/member/profile exists), issuing a PATCH as a same-tenant
  # admin, and asserting the gate still rejects it.
  # -------------------------------------------------------------------------
  describe "allow_admin_member_preview! write-gate invariant" do
    let(:admin) { create(:user, :admin, customer: customer) }

    # Temporarily enable the preview flag on Member::ProfilesController so we
    # can exercise the write-verb branch of enforce_route_role!.
    around do |example|
      original = Member::ProfilesController.admin_member_preview_allowed
      Member::ProfilesController.admin_member_preview_allowed = true
      example.run
    ensure
      Member::ProfilesController.admin_member_preview_allowed = original
    end

    before { sign_in admin }

    it "admits a same-tenant admin GET when the flag is on" do
      get "/#{customer.id}/member/profile"
      # The role gate passes; any non-200 here would be downstream (e.g. 404,
      # redirect from the action itself) — but 403/forbidden from the role gate
      # must NOT be the response.
      expect(response.status).not_to eq(403)
    end

    it "rejects a same-tenant admin PATCH even when the flag is on" do
      patch "/#{customer.id}/member/profile",
            params: { member_profiles_update_contract: { first_name: "Hack" } }
      # RouteAuthorization rejects the write verb for non-members;
      # handle_access_denied issues a redirect (302) for HTML.
      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
      expect(response.status).not_to eq(200)
    end
  end
end
