# frozen_string_literal: true

module EntityDefinitions
  # A choice attribute (select, radio, checkbox, …) either carries its own
  # static options or draws them from another entity's entries.
  #
  # That binding is STORED as `config["entity_id"]` but EXCHANGED with the
  # assistant as `config["options_entity_name"]`, because a record id must
  # never cross the tenant boundary into a prompt. This module is the single
  # translator between the two shapes, so the catalog echo, the persist path
  # and the update policy all agree on which list an attribute is bound to.
  module ChoiceList
    ENTITY_ID_KEY = "entity_id"
    ENTITY_NAME_KEY = "options_entity_name"

    # What list an attribute reads, independent of the shape it arrived in.
    # An entity binding always stores the record id; `label_field` is display
    # only and is deliberately absent.
    Source = Struct.new(:options_source, :entity_name, keyword_init: true)

    module_function

    def names_by_id(customer_id)
      Entity.where(customer_id: customer_id).pluck(:id, :name).to_h
    end

    # Stored config → the shape the assistant is shown. A dangling id is
    # dropped rather than echoed, so a deleted entity cannot leak an integer.
    def to_prompt(config, names_by_id:)
      config = config.to_h.stringify_keys
      return config if config[ENTITY_ID_KEY].blank?

      name = names_by_id[config[ENTITY_ID_KEY].to_i]
      config = config.except(ENTITY_ID_KEY)
      name ? config.merge(ENTITY_NAME_KEY => name) : config
    end

    # Config in either shape → nil for a self-contained list, or a Source.
    # Two configs pointing at the same list compare equal whichever shape they
    # arrived in, so a faithful echo never looks like a change.
    def source_of(config, names_by_id: {})
      config = config.to_h.stringify_keys
      options_source = presence_of(config["options_source"])
      name = presence_of(config[ENTITY_NAME_KEY]) || names_by_id[config[ENTITY_ID_KEY].to_i]
      return nil if options_source.nil? && name.nil?

      Source.new(
        options_source: options_source,
        entity_name: name
      )
    end

    def presence_of(value)
      value.to_s.strip.presence
    end
  end
end
