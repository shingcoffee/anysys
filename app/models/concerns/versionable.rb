# frozen_string_literal: true

# Shared versioning for parents (Flowchart, Entity, Page). Each parent is a
# HEAD: it points at `current_version_id`. Its definition body lives only in
# version rows, whose payloads are stored in a content-addressed table so equal
# payloads across the history share one row.
#
# `current_snapshot` returns the JSON string to store (single-column resources
# read the column directly; Entity serializes its many fields). `content_class`
# names the content-addressed store.
module Versionable
  extend ActiveSupport::Concern

  MAX_VERSIONS = 50

  class_methods do
    # reflection:    has_many name holding versions (e.g. :flowchart_versions)
    # version_class: version row class name string (e.g. "FlowchartVersion")
    # content_class: content-addressed store class name string
    # snapshot / snapshot_reader: method returning the JSON string to store
    # customer_head_reflection: opt-in has_many name for per-customer head
    #   pointers (e.g. :entity_customer_heads). When set, a SHARED resource
    #   supports per-customer definition overrides: reads resolve the current
    #   customer's head when present, else the global default; tenant-path
    #   writes (including customer 81721200) create/advance that customer's
    #   override line. Shared Resources mode writes the global default.
    # foreign_key: explicit FK column on the version table. Only needed when
    #   it doesn't match Rails' default inference from `reflection` (e.g.
    #   reflection :template_versions infers :template_id, but the real
    #   column is :email_template_id — see VersionRecord#acts_as_version's
    #   `parent:`, which must name the same column).
    def acts_as_versionable(reflection:, version_class:, content_class:,
                            snapshot: nil, snapshot_reader: nil,
                            customer_head_reflection: nil, foreign_key: nil)
      self.versionable_options = {
        reflection: reflection,
        content_class: content_class,
        snapshot_reader: snapshot_reader || snapshot,
        customer_head_reflection: customer_head_reflection
      }

      has_many reflection, class_name: version_class, foreign_key: foreign_key, dependent: :destroy
      belongs_to :current_version, class_name: version_class, optional: true
      if customer_head_reflection
        has_many customer_head_reflection, dependent: :destroy
      end
    end
  end

  included do
    class_attribute :versionable_options, instance_writer: false

    # The definition body lives in virtual attributes (not DB columns), so a
    # plain #save never persists it — only commit_version! does. Auto-commit
    # after every save so a body change can never be silently dropped. The
    # commit no-ops when the payload hash is unchanged, so identity-only saves
    # (rename, status, soft-delete) create no version. Controllers/services may
    # set #commit_description / #commit_based_on_version_id before saving to
    # annotate lineage.
    attr_writer :commit_description, :commit_based_on_version_id
    after_save :autocommit_version_snapshot

    # SQLite enforces RESTRICT on the current_version_id FK even though the
    # migration declares on_delete: :nullify. Nullify the pointer before
    # dependent: :destroy fires so the parent row can be deleted.
    before_destroy :nullify_current_version_id_before_destroy
    before_destroy :remember_version_content_ids, prepend: true
    after_destroy :garbage_collect_destroyed_version_contents
  end

  # The versions has_many relation, by configured name.
  def versions_relation
    public_send(self.class.versionable_options[:reflection])
  end

  # The "current" version for display: this customer's override head when
  # present, else the global/default head, else the most recent row.
  # Uses the preloaded association when loaded (no N+1 on list pages).
  def display_current_version
    resolved = resolved_current_version
    return resolved if resolved

    rel = versions_relation
    rel.loaded? ? rel.max_by(&:version_number) : rel.ordered.first
  end

  # JSON string for the current definition (reader hook per resource).
  def current_snapshot
    public_send(self.class.versionable_options[:snapshot_reader])
  end

  def content_class
    self.class.versionable_options[:content_class].constantize
  end

  # ==========================================================================
  # Per-customer overrides (opt-in via customer_head_reflection)
  # ==========================================================================

  # True when this resource type supports per-customer definition overrides.
  def customer_overridable?
    self.class.versionable_options[:customer_head_reflection].present?
  end

  # The has_many relation of per-customer head pointers.
  def customer_heads_relation
    public_send(self.class.versionable_options[:customer_head_reflection])
  end

  # This resource's head-pointer row for a customer, or nil.
  def customer_head_for(cid)
    return nil unless customer_overridable? && cid.present?

    rel = customer_heads_relation
    if rel.loaded?
      rel.target.find { |head| head.customer_id == cid }
    else
      rel.find_by(customer_id: cid)
    end
  end

  # True when this customer has a pinned override of a shared resource.
  def customer_override?(cid = Current.customer_id)
    customer_head_for(cid).present?
  end

  # The customer whose override LINE a read/write targets, or nil for the global
  # default line. nil when: not overridable, not a shared resource, no current
  # customer, or Shared Resources mode (platform path reads/writes the global
  # default). Tenant maintenance — including the platform-owner customer
  # 81721200 — targets that customer's override line.
  def override_customer_id(cid = Current.customer_id)
    return nil unless customer_overridable?
    return nil unless respond_to?(:shared?) && shared?
    return nil if cid.blank? || Current.shared_resources_mode
    cid
  end

  # The version whose definition the given customer should see: their override
  # head if present, else the global version customers follow.
  def resolved_current_version(cid = Current.customer_id)
    line_cid = override_customer_id(cid)
    return current_version if line_cid.nil?
    customer_head_for(line_cid)&.current_version || published_version
  end

  # The global version a customer without an override follows (and an override
  # forks from). Flowchart narrows it to the launched version.
  def published_version
    current_version
  end

  # Drop a customer's override entirely so their reads fall back to the global
  # default: remove their head pointer, their version rows, and orphaned content.
  def reset_customer_override!(cid = Current.customer_id)
    return false unless customer_overridable? && cid.present?
    return false unless respond_to?(:shared?) && shared?

    head     = customer_head_for(cid)
    versions = versions_relation.where(customer_id: cid)
    return false unless head || versions.exists?

    transaction do
      content_ids = versions.distinct.pluck(:content_id)
      head&.destroy
      versions.destroy_all
      garbage_collect_version_content_ids!(content_ids)
    end
    garbage_collect_orphaned_contents!(customer_id: cid)
    association(:current_version).reset
    reload_definition_from_head!
    true
  end

  private

  # Version rows owned by a tenant. owner_cid is the version's customer_id:
  # the resource's own customer_id for the global/default line (NULL for a
  # shared resource), or an overriding customer's id for their line.
  def versions_for_owner(owner_cid)
    versions_relation.where(customer_id: owner_cid)
  end

  # The head version for a request context: an override customer's head, or the
  # global/default head (current_version_id) when override_cid is nil.
  def line_head(override_cid)
    return current_version if override_cid.nil?
    customer_head_for(override_cid)&.current_version
  end

  # Advance the appropriate head to a freshly-created version: a customer's
  # override head when override_cid is present, else the global/default head.
  def promote_line_head!(override_cid, version)
    if override_cid.nil?
      update_column(:current_version_id, version.id)
    else
      customer_heads_relation
        .find_or_initialize_by(customer_id: override_cid)
        .update!(current_version_id: version.id)
    end
  end

  public

  # The version rows of the line the current request targets (own/global line,
  # or the current customer's override line). Used by the versions UI so a
  # customer never sees another tenant's override history.
  def current_line_versions
    versions_for_owner(override_customer_id || customer_id)
  end

  # Head version id of the line the current request targets ("default" marker).
  def current_line_head_version_id
    resolved_current_version&.id
  end

  # Changes whenever the line head does, including a head revised in place,
  # which keeps its id.
  def current_line_head_revision
    resolved_current_version&.updated_at&.utc&.iso8601(6)
  end

  # Commit the current definition as a new immutable version and advance the
  # head. No-ops when the payload is unchanged (hash equal to the current head)
  # and no explicit lineage was requested. Pass `content:` to reference an
  # existing content row (restore/set path) with zero payload copy.
  #
  # Concurrency: lock the parent row + retry the narrow RecordNotUnique race
  # (no-op lock on SQLite). Prune to MAX_VERSIONS, then GC orphaned content.
  #
  # `revise_head: true` (the save path) rewrites the head's content instead
  # when the resource allows it (#revise_head_in_place?) and no explicit
  # lineage was requested.
  def commit_version!(description: nil, based_on_version_id: nil, content: nil, revise_head: false)
    line_cid  = override_customer_id           # nil = global default line
    owner_cid = line_cid || customer_id        # tenant of the version row + content

    if content.nil?
      raw = current_snapshot
      payload = raw.present? ? JSON.parse(raw) : {}
      content = content_class.store!(customer_id: owner_cid, payload: payload)
    end

    # Ensure the no-op guard compares against the true head, not a stale cache
    # left over from an earlier commit in the same request (e.g. bridge sync).
    association(:current_version).reset if persisted?
    head = line_head(line_cid)

    if head&.content_id == content.id && based_on_version_id.blank?
      return head # true no-op: identical definition, no lineage change
    end

    if revise_head && head && based_on_version_id.blank? && revise_head_in_place?(head, line_cid)
      head.update!(content: content, description: description)
      garbage_collect_orphaned_contents!(customer_id: owner_cid)
      return head
    end

    based_on_id =
      if based_on_version_id.present? && versions_for_owner(owner_cid).exists?(id: based_on_version_id)
        based_on_version_id
      elsif head
        head.id
      elsif line_cid
        published_version&.id # first override forks from the version customers follow
      end

    version  = nil
    attempts = 0
    begin
      attempts += 1
      transaction do
        # NB: no lock! here — it would reload the record and wipe the virtual
        # definition attributes (they have no backing column) mid-commit. The
        # partial unique indexes + RecordNotUnique retry below are the guard.
        next_number = versions_for_owner(owner_cid).maximum(:version_number).to_i + 1
        version = versions_relation.create!(
          customer_id: owner_cid,
          version_number: next_number,
          description: description,
          based_on_version_id: based_on_id,
          content: content
        )
        # Promote within the same transaction so the line's head can never be
        # left pointing at the previous head once the new version row exists.
        promote_line_head!(line_cid, version)
      end
    rescue ActiveRecord::RecordNotUnique
      retry if attempts < 3
      raise
    end

    prune_versions!(owner_cid, line_cid)
    garbage_collect_orphaned_contents!(customer_id: owner_cid)
    version
  end

  # Restore-as-new: create a new head version whose content IS the chosen
  # version's existing content row (zero payload copy), with lineage. Then
  # refresh the in-memory definition from that content.
  def restore_as_new!(version)
    committed = commit_version!(description: I18n.t("maint_core.version_descriptions.restored_from", number: version.version_number),
                                based_on_version_id: version.id, content: version.content)
    association(:current_version).reset
    reload_definition_from_head!
    committed
  end

  # Move the head pointer to an existing version without creating a new one.
  def set_current_version!(version)
    # Move the head of the line the current request targets (own/global head, or
    # the current customer's override head) — never another tenant's line.
    promote_line_head!(override_customer_id, version)
    association(:current_version).reset
    reload_definition_from_head!
  end

  # Default no-op; Entity/Flowchart/Page override to repopulate virtual attrs.
  def reload_definition_from_head!; end

  # Virtual definition attributes don't survive #reload (no backing column), so
  # repopulate them from the head content after the row is refetched. Page
  # defines its own #reload (class-level) and calls reload_definition_from_head!
  # there; this covers Entity/Flowchart.
  def reload(*)
    result = super
    reload_definition_from_head!
    result
  end

  private

  # Whether a save may rewrite +head+ on the given line instead of committing a
  # new version. Versions are immutable by default.
  def revise_head_in_place?(_head, _line_cid)
    false
  end

  # Versions pruning must keep besides the newest MAX_VERSIONS.
  def retained_version_ids
    []
  end

  # Content can be reused across version lines (e.g. restoring a global
  # snapshot into an override). Never assume its owner is its only referencer.
  def garbage_collect_orphaned_contents!(customer_id:)
    referenced = versions_relation.klass.unscoped.select(:content_id)
    content_class.where(customer_id: customer_id).where.not(id: referenced).delete_all
  end

  def remember_version_content_ids
    @destroyed_version_content_ids = versions_relation.unscope(where: :customer_id).distinct.pluck(:content_id)
  end

  def garbage_collect_destroyed_version_contents
    garbage_collect_version_content_ids!(@destroyed_version_content_ids)
  end

  def garbage_collect_version_content_ids!(ids)
    referenced = versions_relation.klass.unscoped.select(:content_id)
    content_class.where(id: ids).where.not(id: referenced).delete_all
  end

  # after_save hook: persist any body change as a new version. update_column /
  # create! inside commit_version! bypass save callbacks, so no recursion.
  def autocommit_version_snapshot
    commit_version!(description: (@commit_description.presence || I18n.t("maint_core.version_descriptions.manual_save")),
                    based_on_version_id: @commit_based_on_version_id, revise_head: true)
  ensure
    @commit_description = nil
    @commit_based_on_version_id = nil
  end

  def nullify_current_version_id_before_destroy
    update_column(:current_version_id, nil) if current_version_id.present?
  end

  # Prune a single line (nil = global default line) to MAX_VERSIONS. The head is
  # always the newest row, so it is never pruned; we still defensively repoint if
  # it somehow lands in the pruned set.
  def prune_versions!(owner_cid = customer_id, override_cid = nil)
    pruned_ids = versions_for_owner(owner_cid).ordered.offset(MAX_VERSIONS).ids - retained_version_ids
    return if pruned_ids.empty?
    old = versions_relation.where(id: pruned_ids)
    if override_cid.nil?
      update_column(:current_version_id, nil) if current_version_id.in?(pruned_ids)
    else
      head = customer_head_for(override_cid)
      head.destroy if head && head.current_version_id.in?(pruned_ids)
    end
    versions_relation.where(based_on_version_id: pruned_ids).update_all(based_on_version_id: nil)
    old.destroy_all
  end
end
