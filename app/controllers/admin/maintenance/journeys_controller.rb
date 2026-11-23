# frozen_string_literal: true

module Admin
  module Maintenance
    # Owner-only journey builder through RouteAuthorization (OwnerOnlySurfaces).
    # Journeys are customer-owned, so there is no Shared Resources route, and
    # each belongs to a domain, so they are listed on the domain's workspace
    # on the entities index.
    class JourneysController < ApplicationController
      include PageAudienceRouting
      dashboard_menu_item :maintenance

      before_action :find_journey, only: %i[edit update destroy]

      def new
        @journey = Journey.new(customer_id: current_customer_id, audience_admin: true,
                               entity_domain: EntityDomain.for_customer(current_customer_id).find_by(id: params[:domain_id]),
                               definition: Journeys::Definition.blank.to_h.to_json)
        prepare_editor
      end

      def create
        save(Journey.new(customer_id: current_customer_id), :new, "journeys.admin.flash.created")
      end

      def edit
        prepare_editor
      end

      def update
        save(@journey, :edit, "journeys.admin.flash.updated")
      end

      def destroy
        @journey.destroy!
        redirect_to admin_maintenance_entities_path(current_customer_id, domain_id: @journey.entity_domain_id),
                    status: :see_other, notice: t("journeys.admin.flash.deleted")
      end

      private

      def find_journey
        @journey = Journey.for_customer(current_customer_id).find(params[:id])
      end

      def save(journey, template, notice)
        result = Journeys::Activities::Save.call(journey: journey, params: journey_params, customer_id: current_customer_id)
        return redirect_to(edit_admin_maintenance_journey_path(current_customer_id, result.journey), notice: t(notice)) if result.ok

        @journey = result.journey
        @errors = result.errors
        @submitted_steps = submitted_steps
        @submitted_start = journey_params[:start]&.to_h&.stringify_keys
        prepare_editor
        render template, status: :unprocessable_entity
      end

      def journey_params
        params.require(:journey).permit(:name, :key, :description, :entity_domain_id, visible_audiences: [],
                                        start: [:kind, :entity_id, :key, { when: [:field, { in: [] }] }],
                                        steps: [:key, :kind, :page_id, :label, :record, :repeat, :optional, :conditional, :finish_kind,
                                                :finish_step, :finish_page_id, :finish_message, { inputs: {} }])
      end

      # The rows as posted, so a refused save re-renders each step's chosen
      # page even when the page's new action key was rolled back with it.
      # Nested `inputs` stay a plain string-keyed hash for the editor.
      def submitted_steps
        rows = journey_params[:steps]
        list = rows.respond_to?(:values) ? rows.values : Array(rows)
        list.map { |row| row.respond_to?(:to_h) ? row.to_h.deep_stringify_keys : {} }
      end

      # Step pages: launched ones (this customer's and shared), plus any the
      # journey already points at or the refused form chose, so re-saving
      # never drops a step's page.
      def prepare_editor
        scope = Page.where(customer_id: [current_customer_id, nil])
        chosen = Array(@submitted_steps).flat_map { |row| row.values_at("page_id", "finish_page_id") }.compact_blank
        @pages = scope.launched.or(scope.where(action_key: @journey.steps_definition.steps.flat_map { |step| step_action_keys(step) }))
                      .or(scope.where(id: chosen)).by_name.to_a
        @domains = EntityDomain.for_customer(current_customer_id).by_name.to_a
        @preview_path = preview_path if @journey.persisted?
        domain = EntityDomain.for_customer(current_customer_id).find_by(id: @journey.entity_domain_id)
        @catalog = Journeys::BuilderCatalog.new(pages: @pages, domain: domain, customer_id: current_customer_id,
                                                journey: (@journey if @journey.persisted?))
        @readiness = Journeys::LaunchChecks.new(@journey).errors if @journey.persisted? && @journey.draft? && @errors.blank?
      end

      def step_action_keys(step) = [step.action_key, step.target.to_h["action_key"]].compact

      # The first step's page for the first audience that has one (admin
      # first), on the surface the runtime opens, with the draft preview key.
      # A user step opens on Authentication › Users › New.
      def preview_path
        first = @journey.steps_definition.first_step
        return new_admin_modules_authentication_user_path(current_customer_id, journey: @journey.key) if first&.user?
        return if first&.action_key.blank?

        @journey.visible_audiences.each do |audience|
          page = ::Pages::ActionResolver.page_for(customer_id: current_customer_id, action_key: first.action_key, audience: audience)
          return with_journey_key(run_surface_path(page, nil, audience: audience)) if page
        rescue ActiveRecord::RecordNotFound
          next
        end
        nil
      end

      def with_journey_key(path)
        uri = Addressable::URI.parse(path)
        uri.query_values = (uri.query_values || {}).merge("journey" => @journey.key)
        uri.to_s
      end
    end
  end
end
