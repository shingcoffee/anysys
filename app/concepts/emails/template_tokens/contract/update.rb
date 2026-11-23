# frozen_string_literal: true

module Emails
  module TemplateTokens
    module Contract
      class Update < Reform::Form
        property :label
        property :entity_id
        property :attribute_slug

        validates :label, presence: true, length: { maximum: 100 }
        validates :entity_id, presence: true
        validates :attribute_slug, presence: true
      end
    end
  end
end
