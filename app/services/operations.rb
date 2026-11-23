# frozen_string_literal: true

# Registry of channel-agnostic operations. Each operation class under
# app/services/operations/*.rb that inherits Operations::Base calls register!.
# Framework files in the same directory are constantized by ensure_loaded!
# and do not register themselves.
module Operations
  extend PluginRegistry.build(label: "operation", dir: "app/services/operations", defaults: false)
end
