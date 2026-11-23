# frozen_string_literal: true

# Eager-load member surface sources so SourceRegistry is fully populated
# before the first request. Each source file calls `register!` at load.
#
# Phase 1 fills this in. Empty during Phase 0.
Rails.application.config.to_prepare do
  Member::Sources::Builtin
  Member::Sources::Modules
  Member::Sources::Entities
  Member::Sources::Pages
end
