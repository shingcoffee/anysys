# frozen_string_literal: true

module PageShortcuts
  Target = Data.define(:customer_id, :target_type, :target_id, :controller, :action,
                       :page_slug, :uuid, :canonical_path) do
    def initialize(**attributes)
      # Data freezes the container; freeze string members as well.
      super(**attributes.transform_values { |value| value.is_a?(String) ? value.dup.freeze : value })
    end
  end
end
