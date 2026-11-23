# frozen_string_literal: true

require "rails_helper"

# GET|POST /:cid/admin/maintenance/entities/journeys/generate
# (Admin::Maintenance::JourneyGenerationsController)
RSpec.describe "Admin::Maintenance::JourneyGenerations", type: :request do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, customer: customer, role: :admin) }
  let(:platform_owner) { find_or_create_platform_owner }
  let(:domain) { create(:entity_domain, customer: customer, name: "School") }

  def generate_path(cid = customer.id) = "/#{cid}/admin/maintenance/entities/journeys/generate"

  let(:guard_path) { generate_path }

  it_behaves_like "a platform-owner-guarded GET"

  context "with a domain that has a candidate" do
    include_context "student course association"

    before do
      [student_entity, course_entity].each { |entity| EntityDomains::Memberships.place!(entity, domain) }
    end

    context "as the platform owner on the tenant" do
      before { sign_in platform_owner }

      it "lists each domain's candidates with their steps" do
        get generate_path
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML(response.body)
        group = html.at_css("[data-role='generation-domain']")
        expect(group.at_css("h2").text).to include("School")
        card = group.at_css("[data-role='generation-candidate']")
        expect(card.text).to include("Student", "Course")
        expect(card.at_css("ul")["aria-label"]).to eq(I18n.t("journeys.admin.generation.then_steps", steps: "Course"))
        form = card.at_css("form[action='#{generate_path}']")
        expect(form.at_css("input[name='candidate'][value='create-#{student_entity.id}']")).to be_present
        expect(form.at_css("input[name='domain_id'][value='#{domain.id}']")).to be_present
        expect(group.css("[data-role='generation-kind']").map { |kind| kind["data-kind"] }).to eq(%w[create record])
        expect(group.css("[data-role='generation-candidate']").map { |item| item["data-candidate"] })
          .to include("create-#{course_entity.id}", "record-#{student_entity.id}-#{bridge_entity.id}-student")
        expect(response.body).to include(I18n.t("journeys.admin.generation.intro"))
        expect(html.at_css("main nav a[href='/#{customer.id}/admin/maintenance/entities']")).to be_present
      end

      it "marks a candidate already generated and links to its journey" do
        post generate_path, params: { domain_id: domain.id, candidate: "create-#{student_entity.id}" }
        get generate_path

        card = Nokogiri::HTML(response.body).at_css("[data-candidate='create-#{student_entity.id}']")
        expect(card.at_css("[data-role='generation-existing']").text).to include(I18n.t("journeys.admin.status.draft"))
        expect(card.at_css("[data-role='generation-open']")["href"])
          .to eq("/#{customer.id}/admin/maintenance/entities/journeys/#{Journey.last.id}/edit")
      end

      it "leads back to the domain it was opened from" do
        get generate_path, params: { domain_id: domain.id }

        html = Nokogiri::HTML(response.body)
        expect(html.at_css("[data-role='generation-domain'] h2").text).to include("School")
        expect(html.at_css("main nav a[href='/#{customer.id}/admin/maintenance/entities?domain_id=#{domain.id}']")).to be_present
      end

      it "generates the journey and opens it for review" do
        expect { post generate_path, params: { domain_id: domain.id, candidate: "create-#{student_entity.id}" } }.to change(Journey, :count).by(1)

        journey = Journey.last
        expect(journey).to have_attributes(customer_id: customer.id, entity_domain_id: domain.id)
        expect(journey).to be_draft
        expect(response).to redirect_to("/#{customer.id}/admin/maintenance/entities/journeys/#{journey.id}/edit")
        expect(flash[:notice]).to eq(I18n.t("journeys.admin.flash.generated"))
      end

      it "returns to the candidates with the first error when nothing can be generated" do
        expect { post generate_path, params: { domain_id: domain.id, candidate: "create-0" } }.not_to change(Journey, :count)
        expect(response).to redirect_to("#{generate_path}?domain_id=#{domain.id}")
        expect(flash[:alert]).to eq(I18n.t("journeys.admin.generation.no_candidates"))
      end

      it "404s when generating from another customer's domain" do
        foreign = create(:entity_domain)

        expect { post generate_path, params: { domain_id: foreign.id, candidate: "create-#{student_entity.id}" } }.not_to change(Journey, :count)
        expect(response).to have_http_status(:not_found)
      end
    end

    context "as a tenant admin of the same customer" do
      before { sign_in admin }

      it "is refused on both actions" do
        get generate_path
        expect(response).to have_http_status(:found)
        expect(flash[:alert]).to eq(I18n.t("common.errors.authorization.platform_owner_required"))
        expect { post generate_path, params: { domain_id: domain.id, candidate: "create-#{student_entity.id}" } }.not_to change(Journey, :count)
        post generate_path, params: { domain_id: domain.id, candidate: "create-#{student_entity.id}" }, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "as a member of the same customer" do
      before { sign_in create(:user, :member, customer: customer) }

      it "is refused on both actions" do
        get generate_path
        expect(response).not_to have_http_status(:ok)
        expect { post generate_path, params: { domain_id: domain.id, candidate: "create-#{student_entity.id}" } }.not_to change(Journey, :count)
        get generate_path, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  context "with a domain without candidates" do
    before { sign_in platform_owner }

    it "shows the empty state" do
      domain
      get generate_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("journeys.admin.generation.empty_title"))
      expect(Nokogiri::HTML(response.body).at_css("[data-role='generation-domain']")).to be_nil
    end
  end
end
