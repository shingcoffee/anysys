# frozen_string_literal: true

# Shared behavior for version-snapshot rows (FlowchartVersion, EntityVersion,
# PageVersion). Each version belongs to a parent and to an immutable, content-
# addressed `content` row that holds the JSON payload. `version_number` is
# unique per parent; `based_on_version_id` records lineage.
module VersionRecord
  extend ActiveSupport::Concern

  class_methods do
    # parent:        association name to the owning record (e.g. :flowchart)
    # content_class: class name string of the content-addressed store
    # number_scope:  extra column(s) added to the version_number uniqueness scope.
    #                Entity passes :customer_id so global-default and per-customer
    #                override lines number independently (see Versionable).
    # parent_class_name: explicit class name for the parent association. Only
    #                needed when the parent lives in a namespace that doesn't
    #                match Rails' default inference from the association name
    #                (e.g. :email_template => Emails::Template, not EmailTemplate).
    def acts_as_version(parent:, content_class:, number_scope: [], parent_class_name: nil)
      self.version_parent_name   = parent
      self.version_content_class = content_class

      belongs_to parent, class_name: parent_class_name
      belongs_to :content, class_name: content_class, inverse_of: version_inverse
      belongs_to :based_on_version, class_name: name, optional: true

      validates :content, presence: true
      validates :version_number, presence: true,
                                 uniqueness: { scope: [:"#{parent}_id", *number_scope] }

      scope :ordered, -> { order(created_at: :desc, version_number: :desc) }
      scope :recent,  -> { ordered.limit(50) }
    end

    # has_many name the content model declares back to us, e.g. :entity_versions.
    # #demodulize strips module nesting (Emails::TemplateVersion => TemplateVersion)
    # so a namespaced version class still infers the same plain inverse name its
    # content class declares (:template_versions), matching non-namespaced classes
    # unchanged (PageVersion => :page_versions).
    def version_inverse
      name.demodulize.underscore.pluralize.to_sym
    end
  end

  included do
    class_attribute :version_parent_name, :version_content_class, instance_writer: false
  end

  # Uniform accessor for the snapshot payload (JSON string), read through the
  # content row so the controller JSON contract is unchanged.
  def payload
    content&.payload
  end

  def based_on_version_number
    based_on_version&.version_number
  end
end
