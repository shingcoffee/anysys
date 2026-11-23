# frozen_string_literal: true

module Pages
  # The badge each form shows beside its launch status: "Can't be submitted"
  # for a launched form with submission blockers, otherwise "Out of date" for
  # a form generated from an older version of its entity. One lookup serves
  # the whole list, so queries grow with distinct entities, not with rows.
  class FormHealth
    Status = Data.define(:kind, :problems, :built, :current, :entity_name)

    def self.for(pages, customer_id: Current.customer_id)
      new(pages, customer_id: customer_id).statuses
    end

    def initialize(pages, customer_id:)
      @pages = Array(pages)
      @lookup = LaunchChecks::Lookup.new(customer_id)
    end

    # { page id => Status, or nil when the form needs no badge }
    def statuses
      ids = @pages.filter_map(&:entity_version_id)
      built = ids.empty? ? {} : EntityVersion.where(id: ids).index_by(&:id)
      @pages.to_h { |page| [page.id, status_for(page, built[page.entity_version_id])] }
    end

    private

    def status_for(page, built)
      problems = page.launched? ? page.submission_blockers(lookup: @lookup) : []
      return Status.new(kind: :cannot_submit, problems: problems, built: nil, current: nil, entity_name: nil) if problems.any?

      out_of_date(page, built)
    end

    def out_of_date(page, built)
      entity = @lookup.entity_for(page)
      return unless entity && built

      current = @lookup.current_version(entity)
      return unless page.entity_out_of_date?(current)

      Status.new(kind: :out_of_date, problems: [], built: built.version_number, current: current.version_number,
                 entity_name: entity.display_label.presence || entity.name)
    end
  end
end
