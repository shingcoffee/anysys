# frozen_string_literal: true

# PageLaunchLifecycle
#
# Encapsulates the launch/take-offline workflow and the preflight checks that
# guard it.  Keeps the model free of launch-specific orchestration logic.
#
# Provides:
#   #launch!                  — validates + flips launched = true; raises on failure
#   #take_offline!            — flips launched = false
#   #launchable?              — true when launch_errors is empty
#   #launch_errors            — array of human-readable blocking messages
#   #submission_blockers      — problems that make every submission fail (badges):
#                               no live, compatible processing, required fields missing
#   #orphan_rule_errors       — (private) rule references to deleted fields
#   #orphan_calculation_errors — (private) calculation targets that are missing
#   #field_ids_set            — (private) memoized Set of field IDs in the config
#
module PageLaunchLifecycle
  extend ActiveSupport::Concern

  # Attempt to launch the page.  Raises ActiveRecord::RecordInvalid when there
  # are blocking errors (e.g. missing entity, no fields, orphaned rule refs).
  def launch!
    Customer.transaction do
      Customer.lock.find(customer_id || Authentication::User::PLATFORM_CUSTOMER_ID)
      errs = launch_errors
      if errs.any?
        raise ActiveRecord::RecordInvalid.new(self).tap { errors.add(:base, errs.join("; ")) }
      end

      update!(launched: true)
    end
  end

  # Withdraw the page from its published state.
  def take_offline!
    update!(launched: false)
  end

  # A trashed page keeps launched: true, so restoring it must not claim an
  # action + audience slot another live page took meanwhile.
  def restore
    return super unless launched? && action_key.present?

    restored = false
    Customer.transaction do
      Customer.lock.find(customer_id || Authentication::User::PLATFORM_CUSTOMER_ID)
      collisions = Pages::LaunchChecks.new(self).action_errors
      collisions.each { |message| errors.add(:base, message) }
      restored = collisions.empty? && super
    end
    restored
  end

  # Preflight check before launching — catches broken state that the per-edit
  # validations don't flag (e.g. rule references a deleted field).
  def launchable?
    launch_errors.empty?
  end

  # Collect all blocking messages that would prevent a launch.
  def launch_errors
    msgs = []
    msgs << I18n.t("maint_core.errors.page_launch.entity_missing") unless entity&.active?
    msgs << I18n.t("maint_core.errors.page_launch.no_fields") if fields.empty?
    msgs.concat(orphan_rule_errors)
    msgs.concat(orphan_calculation_errors)
    checks = Pages::LaunchChecks.new(self)
    msgs.concat(checks.reference_errors)
    msgs.concat(checks.audience_errors)
    msgs.concat(checks.identity_errors)
    msgs.concat(checks.action_errors)
    msgs.concat(checks.processing_errors)
    msgs.concat(checks.required_field_errors)
    msgs
  end

  # No live processing, or required fields missing from the form. A list of
  # forms passes one lookup so each record is read once.
  def submission_blockers(lookup: nil)
    Pages::LaunchChecks.new(self, **{ lookup: lookup }.compact).submission_blockers
  end

  private

  # Memoised Set of all field IDs present in the configuration pages.
  def field_ids_set
    @field_ids_set ||= fields.filter_map { |f| f["id"] }.to_set
  end

  # Detect rules that reference field IDs no longer present in the configuration.
  # Rule shape (see Pages::RulesEngine):
  #   conditions is a hash { "logic", "groups" => [{ "items" => [{ "field_id" }] }] }
  #   actions reference fields via "target_id"
  def orphan_rule_errors
    rules = configuration_json&.dig("rules") || []
    ids   = field_ids_set
    rules.filter_map do |rule|
      condition_items = Array(rule.dig("conditions", "groups")).flat_map { |g| Array(g["items"]) }
      referenced = condition_items.map { |i| i["field_id"] } +
                   Array(rule["actions"]).map { |a| a["target_id"] }
      missing = referenced.compact.uniq - ids.to_a
      I18n.t("maint_core.errors.page_launch.rule_missing_fields",
             name: rule["name"] || rule["id"], fields: missing.join(", ")) if missing.any?
    end
  end

  # Detect calculations whose target_field_id no longer exists in the configuration.
  def orphan_calculation_errors
    calcs = configuration_json&.dig("calculations") || []
    ids   = field_ids_set
    calcs.filter_map do |calc|
      target = calc["target_field_id"]
      next if target.blank? || ids.include?(target)

      I18n.t("maint_core.errors.page_launch.calculation_missing_field",
             name: calc["name"] || calc["id"], field: target)
    end
  end
end
