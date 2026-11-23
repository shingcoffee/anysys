# frozen_string_literal: true

module Journeys
  module Activities
    # Turns a planner candidate (EntityDomains::JourneyPlanner, found by its
    # key) into launched pages and a draft journey for the owner to review:
    # - create: the start's admin create page, then an optional, repeatable
    #   step per related row with the start's record locked in; on the person
    #   entity it opens with a user step, so the admin creates the account
    #   first and the person record is linked to it;
    # - record: started from an existing record, one repeatable step adding
    #   that kind of row with the record locked in;
    # - member: a member page on the member's own records, leaving off the
    #   owner reference (the submit fills in the member's) and the attributes
    #   the planner leaves to admins, then an optional, repeatable member step
    #   per row that hangs off it, with that record locked in;
    # - public: a public sign-up page on the person entity (its account fields
    #   first, bound to the sign-up flowchart) that finishes on the member page
    #   the visitor continues on once their email is confirmed.
    # Pages come from Journeys::PageFactory, which reuses a launched page
    # that already fits a step; a page that doesn't fit is left untouched and
    # a new one is built beside it.
    # Everything runs under the customer lock in one transaction, so a
    # failure leaves no stray pages and suffixed keys can't race.
    class Generate
      Result = Struct.new(:ok, :journey, :errors, keyword_init: true)
      START = "start"
      RECORD = "record"
      USER = "user"
      ADMIN = EntityAttributeAudience::ADMIN
      MEMBER = EntityAttributeAudience::MEMBER
      PUBLIC = EntityAttributeAudience::PUBLIC

      def self.call(...) = new(...).call

      def initialize(customer:, domain_id:, candidate_key:)
        @customer = customer
        @domain_id = domain_id
        @candidate_key = candidate_key.to_s
        @errors = []
      end

      def call
        Current.set(customer: @customer, shared_resources_mode: false) do
          journey = nil
          @customer.with_lock(requires_new: true) do
            journey = generate
            raise ActiveRecord::Rollback unless journey
          end
          @errors << I18n.t("journeys.admin.generation.no_candidates") if journey.nil? && @errors.empty?
          Result.new(ok: journey.present?, journey: journey, errors: journey ? [] : @errors.uniq)
        end
      end

      private

      def generate
        domain, candidate = find_candidate
        return unless candidate

        steps = steps_for(candidate)
        persist_journey(domain, candidate, steps) if steps
      end

      def find_candidate
        domain = EntityDomain.for_customer(@customer.id).find_by(id: @domain_id)
        return unless domain

        [domain, Journeys::DomainCandidates.call(customer_id: @customer.id, domain_id: domain.id).find { |candidate| candidate.key == @candidate_key }]
      end

      def steps_for(candidate)
        case candidate.kind
        when :create then create_steps(candidate)
        when :record then record_steps(candidate)
        when :member then member_steps(candidate)
        when :public then public_steps(candidate)
        end
      end

      def create_steps(candidate)
        start = page_for(candidate.start, candidate.page_key, ADMIN)
        relate = start && relate_steps(candidate, START, optional: true)
        user = candidate.user_first? ? [{ "key" => USER, "kind" => "user" }] : []
        [*user, create_step(start), *relate, finish_step(START)] if relate
      end

      def record_steps(candidate)
        relate = relate_steps(candidate, RECORD, optional: false)
        [{ "key" => RECORD, "kind" => "record", "entity_id" => candidate.start.id.to_s }, *relate, finish_step(RECORD)] if relate
      end

      def member_steps(candidate)
        page = member_page(candidate)
        relate = page && relate_steps(candidate, START, optional: true, audience: MEMBER)
        [create_step(page), *relate, finish_step(START)] if relate
      end

      def member_page(candidate)
        page_for(candidate.start, candidate.page_key, MEMBER, name: candidate.name, drop: member_drops(candidate))
      end

      # An anonymous visitor has no record view, so a sign-up with nothing to
      # continue on ends on the page's own landing.
      def public_steps(candidate)
        follow = candidate.follow && member_page(candidate.follow)
        return if candidate.follow && !follow

        flowchart = Flowcharts::SignUpPageFlowchart.for_customer(@customer)
        unless flowchart
          @errors << I18n.t("journeys.generate.signup_unavailable")
          return
        end

        page = page_for(candidate.start, candidate.page_key, PUBLIC, name: candidate.name, signup: flowchart)
        return unless page

        target = follow ? { "kind" => "page", "action_key" => follow.action_key } : { "kind" => "record", "step" => START }
        [create_step(page), { "key" => "finish", "kind" => "finish", "target" => target }]
      end

      # nil as soon as one step's page can't be built. A member page leaves off
      # the row's owner reference, which the submit fills in.
      def relate_steps(candidate, source, optional:, audience: ADMIN)
        candidate.steps.each_with_index.map do |step, index|
          name = I18n.t("journeys.generate.relate_page_name", target: step.label, parent: candidate.start.display_label)
          input = { "field" => step.parent_slug, "entity_id" => candidate.start.id.to_s }
          drop = audience == MEMBER ? [People::Ownership.owner_reference(step.entity)&.slug].compact.map(&:to_s) : []
          page = page_for(step.entity, step.page_key, audience, name: name, input: input, drop: drop)
          return unless page

          { "key" => "relate_#{index + 1}", "kind" => "relate", "action_key" => page.action_key,
            "inputs" => { step.parent_slug => source }, "repeat" => true, "optional" => optional }
        end
      end

      def create_step(page) = { "key" => START, "kind" => "create", "action_key" => page.action_key }
      def finish_step(source) = { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => source } }

      # The member's own person record is the owner, so the field never shows.
      def member_drops(candidate)
        owner = People::Ownership.owner_reference(candidate.start)&.slug
        [owner, *candidate.left_out.map { |attribute| attribute["name_slug"] }].compact.map(&:to_s)
      end

      def persist_journey(domain, candidate, steps)
        Journey.create!(
          customer: @customer, entity_domain: domain, status: :draft, visible_audiences: [candidate.audience],
          key: unique_key(candidate.journey_key) { |key| Journey.where(customer_id: @customer.id).exists?(key: key) },
          name: candidate.name.first(120), definition: { "steps" => steps }.to_json
        )
      rescue ActiveRecord::RecordInvalid => e
        @errors.concat(e.record.errors.full_messages)
        nil
      end

      def page_for(entity, key, audience, **)
        @pages ||= Journeys::PageFactory.new(customer: @customer, errors: @errors)
        @pages.page_for(entity, key, audience, **)
      end

      def unique_key(base)
        (1..).lazy.map { |attempt| attempt == 1 ? base : "#{base}_#{attempt}" }.find { |key| !yield(key) }
      end
    end
  end
end
