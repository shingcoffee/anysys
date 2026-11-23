# frozen_string_literal: true

class FlowchartVersion < ApplicationRecord
  include VersionRecord

  # customer_id in the numbering scope: the global-default line (customer_id NULL)
  # and each customer's override line number independently (v1, v2, …).
  acts_as_version parent: :flowchart, content_class: "FlowchartConfigurationContent",
                  number_scope: :customer_id
end
