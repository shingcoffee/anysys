# frozen_string_literal: true

class PageVersion < ApplicationRecord
  include VersionRecord

  acts_as_version parent: :page, content_class: "PageConfigurationContent",
                  number_scope: :customer_id
end
