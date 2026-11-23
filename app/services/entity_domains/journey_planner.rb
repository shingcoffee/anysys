# frozen_string_literal: true

module EntityDomains
  # Proposes the journeys one domain supports, from its entity graph and who
  # owns which records. A domain usually needs several, each for its own
  # audience and starting point:
  #
  # - create: an admin creates a record, then adds the rows that hang off it —
  #   links through a bridge declared on either end, and child records that
  #   reference it. Every record type gets one, so a catalog record (a course)
  #   has a guided start too.
  # - record: an admin starts from an existing record's page and adds one kind
  #   of related row, as that page's "+ Add" does.
  # - member: a member starts on a page for records they own (the owner
  #   reference points at their person record), which the submit links to
  #   them, then adds the rows that hang off it (a booking's guests) with that
  #   record locked in: rows nobody owns, or rows the same person owns. On a
  #   link they make the choice and fill what the link requires; link
  #   attributes admins can see but members needn't fill (a grade, an
  #   enrolment date) stay with admins.
  # - public: when the domain has a person entity, a visitor signs up as a
  #   member on a public page for it. Once they confirm their email they
  #   continue on a member page (one candidate per member journey), or, when
  #   the domain has none, the journey just ends on sign-up.
  #
  # The person entity's own create journey opens by creating its user
  # account, and the person record it saves is linked to that account.
  #
  # An admin page on a member-owned link must lock the owner
  # (Pages::LaunchChecks#bridge_member_only_errors), so such a link is only
  # related from the owner's side. Bridges are never a journey's start.
  class JourneyPlanner
    ADMIN = EntityAttributeAudience::ADMIN
    MEMBER = EntityAttributeAudience::MEMBER
    PUBLIC = EntityAttributeAudience::PUBLIC
    # Keeps "<start>_add_<label>_journey_<n>" inside PageVisibility::ACTION_KEY's 63 characters.
    SLUG_LENGTH = 24
    DERIVED_TYPES = %w[Calculated Computed].freeze

    # +page_key+: base action key of the page the journey opens on (nil when
    # it starts from a record). +left_out+: attributes a member page leaves
    # to admins. +follow+: the member candidate a public sign-up continues
    # into after the email is confirmed.
    Candidate = Data.define(:key, :kind, :audience, :start, :steps, :name, :page_key, :journey_key, :left_out, :follow) do
      def initialize(follow: nil, **rest) = super

      def create? = kind == :create
      def record? = kind == :record
      def member? = kind == :member
      def public? = kind == :public
      def user_first? = create? && start.person?
    end
    # +link+: the step adds a bridge's rows, linking the start to a chosen record.
    RelateStep = Data.define(:entity, :parent_slug, :label, :link, :page_key)

    def self.call(...) = new(...).candidates

    def self.slug(text, entity)
      value = SectionSlug.for(text).first(SLUG_LENGTH).delete_suffix("_")
      value.match?(/\A[a-z]/) ? value : "entity_#{entity.id}"
    end

    def self.create_page_key(entity) = "#{slug(entity.name, entity)}_new"

    def initialize(customer_id:, entities:)
      @customer_id = customer_id
      @entities = Array(entities)
    end

    def candidates
      @candidates ||= create_candidates + record_candidates + member_candidates + public_candidates
    end

    def find(key) = candidates.find { |candidate| candidate.key == key.to_s }

    private

    def starts = @starts ||= @entities.reject(&:bridge_entity?)

    def create_candidates
      starts.map do |entity|
        base = slug(entity.name, entity)
        Candidate.new(key: "create-#{entity.id}", kind: :create, audience: ADMIN, start: entity, steps: related_steps(entity),
                      name: I18n.t("journeys.generate.journey_name", start: entity.display_label),
                      page_key: self.class.create_page_key(entity), journey_key: "#{base}_journey", left_out: [])
      end.sort_by { |candidate| [-candidate.steps.size, declares_links?(candidate.start) ? 0 : 1, sort_label(candidate.start)] }
    end

    def record_candidates
      starts.flat_map do |entity|
        related_steps(entity).map do |step|
          Candidate.new(key: "record-#{entity.id}-#{step.entity.id}-#{step.parent_slug}", kind: :record, audience: ADMIN,
                        start: entity, steps: [step],
                        name: I18n.t("journeys.generate.relate_page_name", target: step.label, parent: entity.display_label),
                        page_key: nil, journey_key: "#{step.page_key}_journey", left_out: [])
        end
      end.sort_by { |candidate| [sort_label(candidate.start), candidate.steps.first.label.downcase] }
    end

    def member_candidates
      @member_candidates ||= @entities.filter_map do |entity|
        descriptor = People::Ownership.describe(entity)
        next unless descriptor.kind == :owned

        entity.bridge_entity? ? link_candidate(entity, descriptor.owner) : owned_record_candidate(entity)
      end.sort_by { |candidate| candidate.name.downcase }
    end

    # Each public journey opens on its own sign-up page, since a page starts
    # at most one live journey per audience.
    def public_candidates
      person = starts.find(&:person?)
      return [] unless person

      follows = member_candidates
      follows.empty? ? [signup_candidate(person, nil)] : follows.map { |follow| signup_candidate(person, follow) }
    end

    def signup_candidate(person, follow)
      base = follow ? follow.page_key.sub(/\Amember_/, "signup_") : "signup_#{slug(person.display_label, person)}"
      name =
        if follow
          I18n.t("journeys.generate.signup_then_name", next: follow.name)
        else
          I18n.t("journeys.generate.signup_name", entity: person.display_label)
        end
      Candidate.new(key: "public-#{(follow&.start || person).id}", kind: :public, audience: PUBLIC, start: person, steps: [],
                    name: name, page_key: base, journey_key: "#{base}_journey", left_out: [], follow: follow)
    end

    def link_candidate(bridge, owner)
      schema = Array(bridge.property_schema_json).grep(Hash)
      choice = schema.find { |attribute| participant?(attribute) && attribute["name_slug"] != owner.slug }
      target = choice && entity_for(Entities::BridgeParticipants.referenced_entity_id(choice))
      return unless target

      base = "member_choose_#{slug(target.display_label, target)}"
      Candidate.new(key: "member-#{bridge.id}", kind: :member, audience: MEMBER, start: bridge, steps: [],
                    name: I18n.t("journeys.generate.member_choose_name", target: target.display_label),
                    page_key: base, journey_key: "#{base}_journey", left_out: left_to_admins(schema, owner))
    end

    def owned_record_candidate(entity)
      base = "member_new_#{slug(entity.display_label, entity)}"
      Candidate.new(key: "member-#{entity.id}", kind: :member, audience: MEMBER, start: entity, steps: member_steps(entity),
                    name: I18n.t("journeys.generate.member_new_name", entity: entity.display_label),
                    page_key: base, journey_key: "#{base}_journey", left_out: [])
    end

    # Hidden from members, or shown to both but required of neither: the
    # member page leaves these to admins. Member-only attributes stay.
    def left_to_admins(schema, owner)
      schema.select do |attribute|
        slug = attribute["name_slug"].to_s
        next false if slug.blank? || slug == owner.slug || participant?(attribute) || derived?(attribute)

        EntityAttributeAudience.visible_to?(attribute, ADMIN) &&
          !(EntityAttributeAudience.visible_to?(attribute, MEMBER) && required_for_member?(attribute))
      end
    end

    def related_steps(entity) = relatable_steps(entity).select { |step| admin_relatable?(step) }

    def member_steps(entity)
      owner = People::Ownership.owner_reference(entity)
      relatable_steps(entity).select { |step| member_relatable?(step, owner) }
                             .map { |step| step.with(page_key: "member_#{step.page_key}") }
    end

    def relatable_steps(entity)
      @relatable_steps ||= {}
      @relatable_steps[entity.id] ||= (declared_links(entity) + inverse_links(entity) + child_steps(entity))
                                      .uniq { |step| [step.entity.id, step.parent_slug] }
                                      .sort_by { |step| [step.link ? 0 : 1, step.label.downcase] }
    end

    def declared_links(entity)
      entity.associations_list.filter_map do |association|
        bridge = domain_entity(association["bridge_entity_id"])
        target = domain_entity(association["target_entity_id"])
        relate(entity, bridge, target, link: true) if bridge && target
      end
    end

    # Links another entity declares towards this one, added from this end:
    # the page picks the declaring entity's record, so that entity needs a
    # field to label its records by (as Entities::EntryAssociations#inverse).
    def inverse_links(entity)
      starts.reject { |other| other.id == entity.id }.flat_map do |other|
        other.associations_list.select { |association| association["target_entity_id"].to_s == entity.id.to_s }.filter_map do |association|
          bridge = domain_entity(association["bridge_entity_id"])
          relate(entity, bridge, other, link: true) if bridge && pickable?(other)
        end
      end
    end

    def child_steps(entity)
      starts.reject { |other| other.id == entity.id }.filter_map { |child| relate(entity, child, child, link: false) }
    end

    def relate(start, entity, named, link:)
      parent_slug = reference_slug(entity, start)
      return unless parent_slug

      label = named.display_label.to_s
      RelateStep.new(entity: entity, parent_slug: parent_slug, label: label, link: link,
                     page_key: "#{slug(start.name, start)}_add_#{slug(label, entity)}")
    end

    def admin_relatable?(step)
      return true unless step.link

      descriptor = People::Ownership.describe(step.entity)
      descriptor.kind != :owned || descriptor.owner.slug == step.parent_slug
    end

    # The member reaches the row through the locked record, and the submit
    # fills a same-person owner reference with theirs. A row that also
    # references a private record type could not launch on a member page.
    def member_relatable?(step, owner)
      descriptor = People::Ownership.describe(step.entity)
      fits = case descriptor.kind
             when :open then true
             when :owned then descriptor.owner.person_entity_id == owner.person_entity_id
             when :nested then descriptor.parents.any? { |parent| parent.slug == step.parent_slug }
             else false
             end
      fits && Array(step.entity.property_schema_json).grep(Hash).none? do |attribute|
        id = Entities::BridgeParticipants.referenced_entity_id(attribute)
        target = id.present? && entity_for(id)
        target && People::Ownership.kind(target) == :private
      end
    end

    # The same reference rule a page's locked input is validated against.
    def reference_slug(entity, target)
      Array(entity.property_schema_json).grep(Hash).find do |attribute|
        Entities::BridgeParticipants.referenced_entity_id(attribute) == target.id.to_s
      end&.dig("name_slug")
    end

    def participant?(attribute) = Entities::BridgeParticipants.referenced_entity_id(attribute).present?
    def derived?(attribute) = DERIVED_TYPES.include?(attribute["type"]) || attribute["storage"] == "computed"

    def required_for_member?(attribute)
      requiring = Array(attribute["validators"]).any? do |validator|
        validator.is_a?(Hash) && ValidatorRegistry::REQUIRING_VALIDATIONS.include?(validator["type"].to_s.to_sym)
      end
      requiring && EntityAttributeAudience.applying_audiences(attribute).include?(MEMBER)
    end

    def pickable?(entity) = Entities::BridgeParticipants.label_field(entity.id, @customer_id).present?
    def declares_links?(entity) = entity.associations_list.any?

    def domain_entity(id) = @entities.find { |entity| entity.id.to_s == id.to_s }
    def entity_for(id) = domain_entity(id) || Entity.where(customer_id: [@customer_id, nil]).find_by(id: id)
    def slug(text, entity) = self.class.slug(text, entity)
    def sort_label(entity) = entity.display_label.to_s.downcase
  end
end
