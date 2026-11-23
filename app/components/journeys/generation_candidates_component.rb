# frozen_string_literal: true

module Journeys
  # The journeys the customer's domains can generate, grouped by domain and
  # then by where they start (EntityDomains::JourneyPlanner kinds): one card
  # per candidate with its audience, start, the steps that follow, what a
  # member page leaves to admins, and the journey already generated from it,
  # each with its own generate button. `groups` are `[domain, candidates]`
  # pairs; `journeys` are the customer's journeys in those domains.
  class GenerationCandidatesComponent < ApplicationComponent
    KINDS = %i[create record member public].freeze
    AUDIENCE_VARIANTS = { "admin" => :info, "member" => :success, "public" => :warning }.freeze

    attr_reader :groups

    def initialize(groups:, customer_id:, journeys: [])
      @groups = Array(groups)
      @customer_id = customer_id
      @journeys = Array(journeys)
    end

    def generate_path = helpers.generate_admin_maintenance_journeys_path(@customer_id)
    def domain_dot(domain) = EntityDomainColors.dot(domain.color)
    def kind_groups(candidates)
      KINDS.filter_map do |kind|
        list = candidates.select { |candidate| candidate.kind == kind }
        [kind, list] if list.any?
      end
    end

    def kind_title(kind) = t("journeys.admin.generation.kinds.#{kind}.title")
    def kind_hint(kind) = t("journeys.admin.generation.kinds.#{kind}.hint")
    def kind_heading_id(domain, kind) = "journey-domain-#{domain.id}-#{kind}"

    def audience_label(candidate) = t("journeys.audiences.#{candidate.audience}")
    def audience_variant(candidate) = AUDIENCE_VARIANTS.fetch(candidate.audience, :default)

    def start_label(candidate)
      entity = candidate.start.display_label
      if candidate.user_first? then t("journeys.admin.generation.starts.user", entity: entity)
      elsif candidate.create? then t("journeys.admin.generation.starts.create", entity: entity)
      elsif candidate.record? then t("journeys.admin.generation.starts.record", entity: entity)
      elsif candidate.public? then t("journeys.admin.generation.starts.public", entity: entity)
      else t("journeys.admin.generation.starts.member")
      end
    end

    # What follows when no related rows do: the record opens, or a sign-up
    # continues on a member page once the email is confirmed.
    def then_note(candidate)
      return t("journeys.admin.generation.opens_record") unless candidate.public?
      return t("journeys.admin.generation.signup_done") unless candidate.follow

      t("journeys.admin.generation.continues_as_member", name: candidate.follow.name)
    end

    def left_to_admins(candidate)
      return if candidate.left_out.empty?

      names = candidate.left_out.map { |attribute| attribute["name"].presence || attribute["name_slug"] }
      t("journeys.admin.generation.left_to_admins", fields: names.join(t("support.array.words_connector")))
    end

    def step_count_label(candidate)
      t("journeys.admin.step_count", count: candidate.steps.size + (candidate.user_first? ? 2 : 1))
    end

    # The latest journey generated from the candidate in that domain: its key
    # is the candidate's journey key, suffixed when generated again.
    def generated(domain, candidate)
      family = /\A#{Regexp.escape(candidate.journey_key)}(_\d+)?\z/
      @journeys.reverse.find { |journey| journey.entity_domain_id == domain.id && journey.key.match?(family) }
    end

    def journey_path(journey) = helpers.edit_admin_maintenance_journey_path(@customer_id, journey)
  end
end
