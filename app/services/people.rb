# frozen_string_literal: true

# Person-entity entries may carry identity in JSON `data` until they are
# linked to a User. These reserved keys match Authentication::User columns
# and cannot appear as attribute slugs on an extension of PERSON_MODEL.
module People
  IDENTITY_KEYS = %w[first_name last_name email].freeze
end
