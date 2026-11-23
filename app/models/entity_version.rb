# frozen_string_literal: true

class EntityVersion < ApplicationRecord
  include VersionRecord

  # customer_id in the numbering scope: the global-default line (customer_id NULL)
  # and each customer's override line number independently (v1, v2, …).
  acts_as_version parent: :entity, content_class: "EntityDefinitionContent",
                  number_scope: :customer_id
end
