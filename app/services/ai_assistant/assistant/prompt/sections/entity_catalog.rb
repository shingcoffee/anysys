# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        # The tenant's live entity definitions in the public vocabulary.
        class EntityCatalog < Section
          heads "This workspace's entities"

          private

          def body
            <<~TEXT
              #{domains_copy}

              #{entities_copy}
            TEXT
          end

          def domains_copy
            <<~TEXT
              Domains (sub-systems) in this workspace. Every entity belongs to one domain.
              Call `create_domain` to start a new business area, then `create_entity` with that `domain` name.
              Adding to an existing sub-system: reuse its name from this list. Never invent a domain name that is not listed unless you create it first.

              ```json
              #{json(context.domain_catalog)}
              ```
            TEXT
          end

          def entities_copy
            catalog = context.entity_catalog
            return "This workspace has no entities yet. Anything you define is a create." if catalog.empty?

            <<~TEXT
              Live customer-owned entity definitions in this tenant, in the public vocabulary.
              A `name` that matches one of these already exists — call `get_entity` then `update_entity`.
              Any other name is a `create_entity`. Groups use `key`; attributes reference them with `group`.

              ```json
              #{json(catalog)}
              ```
            TEXT
          end
        end
      end
    end
  end
end
