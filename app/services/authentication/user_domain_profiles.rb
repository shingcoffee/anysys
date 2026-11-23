# frozen_string_literal: true

module Authentication
    # Profiles for an admin user detail page in the URL tenant. Start from
    # definitions so an eligible type is visible even without an explicit
    # account link; navigation roots and identity data do not determine links.
    # A linked profile carries its entry, display and association rows, and
    # whether the viewer may add association rows; a missing one carries the
    # Create Entry form when the viewer may create and link it (+forms+
    # replaces that form by entity id, e.g. after a failed submission).
    class UserDomainProfiles
    Section = Data.define(:domain, :profiles)
    Profile = Data.define(:entity, :entry, :display, :groups, :associations, :form, :associations_writable) do
      def initialize(associations_writable: false, **) = super
    end

    def self.call(...) = new(...).call

    def initialize(user:, customer:, viewer:, forms: {})
      @user = user
      @customer = customer
      @viewer = viewer
      @forms = forms
    end

    def call
      authorize!
      Current.set(customer: @customer, shared_resources_mode: false) { sections }
    end

    private

    def authorize!
      unless @customer&.persisted? && @user&.persisted? && @user.customer_id == @customer.id
        raise ActiveRecord::RecordNotFound
      end
      return if @viewer&.admin_or_owner? && EntityAttributeAudience.tenant_viewer?(@viewer, customer_id: @customer.id)

      raise CanCan::AccessDenied, I18n.t("common.flash.access_denied")
    end

    def ability
      @ability ||= Ability.new(@viewer)
    end

    def profile_entities
      return [] unless ability.can?(:read, :route_admin_entities) && ability.can?(:read, :route_admin_entity_entries)

      EntityDomains::Catalog.entities(@customer.id).active.non_bridge
                   .where(extended_model: EntityDefinitions::Capabilities::PERSON_MODEL)
                   .select { |entity| entity.person? && ability.can?(:read, entity) }
                   .sort_by { |entity| [entity.display_label.to_s.downcase(:fold), entity.id] }
    end

    def sections
      entities = profile_entities
      return [] if entities.empty?

      entries = EntityEntry.where(customer_id: @customer.id, user_id: @user.id, entity_id: entities.map(&:id))
                           .index_by(&:entity_id)
      EntityDomains::Layout.call(customer_id: @customer.id, entities: entities).filter_map do |section|
        next if section.items.empty?

        Section.new(domain: section.domain,
                    profiles: section.items.map { |item| profile_for(item.entity, entries[item.entity.id]) })
      end
    end

    def profile_for(entity, entry)
      unless entry
        return Profile.new(entity: entity, entry: nil, display: nil, groups: [], associations: [], form: form_for(entity))
      end

      # Reuse the URL-tenant effective definition loaded by Entity#after_find.
      # DerivedValues reads through entry.entity as well as the display's entity.
      entry.entity = entity
      groups = groups_for(entity)
      display = Entities::EntryDisplay.new(entity: entity, entries: [entry], customer_id: @customer.id,
                                            audience: EntityAttributeAudience::ADMIN, viewer: @viewer)
      associations = Entities::EntryAssociations.new(entity: entity, customer: @customer).sections(entry)
      Profile.new(entity: entity, entry: entry, display: display, groups: groups, associations: associations, form: nil,
                  associations_writable: associations_writable?)
    end

    def associations_writable?
      return @associations_writable if defined?(@associations_writable)

      @associations_writable = ability.can?(:create, :route_admin_entity_association_entries)
    end

    # People::Contracts::Link only links active accounts.
    def form_for(entity)
      return unless @user.active? && ability.can?(:create, :route_admin_modules_authentication_user_profiles)

      @forms[entity.id] || Entities::EntryForm.new(entity: entity, customer: @customer)
    end

    def groups_for(entity)
      entity.grouped_property_schema.filter_map do |section|
        fields = Array(section[:attributes]).grep(Hash).select do |field|
          field["name_slug"].present? && EntityAttributeAudience.visible_to?(field, EntityAttributeAudience::ADMIN)
        end
        next if fields.empty?

        group = section[:group] || {}
        {
          key: group["id"].presence || "other",
          heading: group["name"].presence || group["label"].presence || I18n.t("admin_misc.entities.entry_detail.ungrouped"),
          icon: group["icon"],
          color: group["color"],
          fields: fields
        }
      end
    end
  end
end
