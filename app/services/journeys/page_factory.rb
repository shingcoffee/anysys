# frozen_string_literal: true

module Journeys
  # Builds the launched pages journey steps run on, for the owner's journey
  # generator (Journeys::Activities::Generate) and the assistant's sub-system
  # builds (AiAssistant::Subsystems::AssembleJourney). A new page binds the
  # shared "Save page record" (or sign-up) flowchart, or the customer's own
  # copy once the platform owner has deleted it. Callers hold the customer
  # lock and roll back when a page fails; failures land in +errors+.
  class PageFactory
    ADMIN = EntityAttributeAudience::ADMIN
    IDENTITY_HTML_TYPES = { "email" => "email" }.freeze
    LAYOUT_TYPES = %w[columns].freeze

    attr_reader :errors

    def initialize(customer:, errors: [])
      @customer = customer
      @errors = errors
    end

    # A launched page of the customer's own that already fits (same entity
    # and audience, generated key, adds records, locks the same input) is
    # reused, so generating twice doesn't duplicate forms.
    # +signup+: the sign-up flowchart a public sign-up page binds.
    def page_for(entity, key, audience, name: nil, input: nil, drop: [], signup: nil)
      reusable_page(entity, key, audience, input, signup) ||
        create(entity, key, audience, name: name, inputs: [input].compact, drop: drop, signup: signup)
    end

    # A new launched page. +only+: the attribute slugs to keep, in the
    # template's order (nil keeps them all). +modes+: create and/or update.
    def create(entity, base, audience, name: nil, inputs: [], drop: [], only: nil, modes: %w[create], signup: nil, success_message: nil)
      page = new_page(entity, admin_form: audience == ADMIN && inputs.empty? && signup.nil? && only.nil? && modes == %w[create])
      return unless page

      config = page.configuration_json
      settings = config["form_settings"].is_a?(Hash) ? config["form_settings"] : {}
      settings["modes"] = modes
      settings["inputs"] = inputs if inputs.any?
      settings["success_message"] = success_message if success_message.present?
      config = shape_fields(config.merge("form_settings" => settings), entity, inputs.first, drop, only)
      page.configuration_json = signup ? with_identity_fields(config) : config
      page.flowchart = signup || page.flowchart || Flowcharts::DefaultPageFlowchart.for_customer(@customer)
      page.action_key = Pages::ActionKeys.unique(base, customer_id: @customer.id)
      page.name = name.first(100) if name
      page.visible_audiences = [audience]
      page.commit_description = I18n.t("journeys.generate.version_description")
      page.save!
      page.launch!
      page
    rescue ActiveRecord::RecordInvalid => e
      @errors.concat(e.record.errors.full_messages)
      nil
    end

    private

    # A form built from an earlier version of the entity misses fields
    # added since, so the one built from the current version wins.
    def reusable_page(entity, base, audience, input, signup)
      family = /\A#{Regexp.escape(base)}(_\d+)?\z/
      fitting = Page.where(customer_id: @customer.id, launched: true).for_audience(audience).for_entity(entity.id).order(:id).select do |page|
        page.action_key.to_s.match?(family) && page.serves?(:create) && page.page_inputs == [input].compact &&
          (signup.nil? || signs_up?(page, signup))
      end
      current = entity.resolved_current_version(@customer.id)&.id
      fitting.find { |page| current && page.entity_version_id == current } || fitting.first
    end

    def signs_up?(page, flowchart)
      page.flowchart_id == flowchart.id && page.input_fields.any? { |field| Pages::FormParams.identity_field?(field) }
    end

    # A bridge stores its declaring participant as a bare id; choosing it
    # needs the labelled dropdown the record page uses (BridgeParticipants).
    def shape_fields(config, entity, input, drop, only)
      pickers = entity.bridge_entity? ? picker_options(entity, input) : {}
      return config if pickers.empty? && drop.empty? && only.nil?

      keep = only&.map(&:to_s)
      config.merge("pages" => Array(config["pages"]).map do |step|
        step.is_a?(Hash) ? step.merge("fields" => shape(Array(step["fields"]), pickers, drop, keep)) : step
      end)
    end

    def shape(fields, pickers, drop, keep)
      fields.filter_map do |field|
        next field unless field.is_a?(Hash)
        if LAYOUT_TYPES.include?(field["field_type"])
          next field.merge("columns" => Array(field["columns"]).map { |column| shape_column(column, pickers, drop, keep) })
        end

        slug = field["property_slug"].to_s
        next field if slug.empty?
        next if drop.include?(slug) || (keep && !keep.include?(slug))

        options = pickers[slug]
        next field unless options

        field.merge("field_type" => "select", "html_type" => "select", "dynamic_options" => options,
                    "property_type" => PageFieldPopulator::HTML_TYPE_TO_PROPERTY_TYPE["select"])
      end
    end

    def shape_column(column, pickers, drop, keep)
      column.is_a?(Hash) ? column.merge("fields" => shape(Array(column["fields"]), pickers, drop, keep)) : column
    end

    # The account's name and email open the form, as the page editor's
    # identity fields: register_member creates the member from them.
    def with_identity_fields(config)
      pages = Array(config["pages"]).dup
      first = pages.first.is_a?(Hash) ? pages.first : { "id" => "page_1", "order" => 1, "fields" => [] }
      fields = People::IDENTITY_KEYS.map { |key| identity_field(key) } + Array(first["fields"])
      pages[0] = first.merge("fields" => fields.each_with_index.map { |field, index| field.is_a?(Hash) ? field.merge("order" => index) : field })
      config.merge("pages" => pages)
    end

    def identity_field(key)
      html_type = IDENTITY_HTML_TYPES.fetch(key, "text")
      { "id" => "field_#{SecureRandom.hex(8)}", "field_type" => html_type, "property_slug" => key,
        "property_type" => PageFieldPopulator::HTML_TYPE_TO_PROPERTY_TYPE[html_type], "label" => I18n.t("member.profiles.show.fields.#{key}"),
        "placeholder" => "", "help_text" => "", "required" => true, "width" => "full", "source" => "identity", "html_type" => html_type }
    end

    def picker_options(entity, input)
      schema = Array(entity.property_schema_json).grep(Hash)
      Entities::BridgeParticipants.pickers(schema, customer_id: @customer.id).zip(schema).each_with_object({}) do |(picker, attribute), map|
        slug = attribute["name_slug"].to_s
        next unless Entities::BridgeParticipants.bare?(attribute) && picker["config"].is_a?(Hash) && slug != input&.dig("field")

        map[slug] = picker["config"].slice("options_source", "entity_id", "label_field")
      end
    end

    # The entity-version generator keeps one page per version and restores
    # a trashed one, so when the customer already has a page for that
    # version, live or trashed, a hand-built one (the admin "new page"
    # path) is composed from the same version instead of taking it over.
    # Only the plain admin create page takes the version page: the
    # assistant's page generator reuses that page as the entity's admin
    # form, which a page with a locked input, another audience or a subset
    # of the fields can't be.
    def new_page(entity, admin_form:)
      version = entity.resolved_current_version(@customer.id)
      return composed_page(entity, version) if !admin_form || version.nil? || version_page?(version)

      result = Pages::Activities::CreateFromEntityVersion.call(entity: entity, version: version, customer: @customer, shared: false)
      return result.page if result.ok

      @errors << result.message
      nil
    end

    def version_page?(version) = Page.with_deleted.where(customer_id: @customer.id, entity_version_id: version.id).exists?

    def composed_page(entity, version)
      guard = Billing::Quota::Guard.check(customer: @customer, item_key: "page")
      unless guard.allowed?
        @errors << guard.message
        return
      end

      page = Page.new_with_defaults(customer: @customer, name: (entity.display_label.presence || entity.name).first(100))
      page.entity_id = entity.id
      Pages::ConfigurationComposer.call(page: page, template_key: "default", theme_preset_key: nil,
                                        entity: version ? Entities::VersionHydrator.hydrate(entity, version) : entity)
      page
    end
  end
end
