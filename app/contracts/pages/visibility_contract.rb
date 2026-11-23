# frozen_string_literal: true

module Pages
  # Accepts a `visible_audiences` checkbox array and `action_key` from the
  # form and maps them onto the page's audience booleans. Unknown audience
  # names are ignored. An empty set is invalid (`page_audiences_blank`).
  #
  # Adding an audience to a launched page re-runs the dropdown, required-field,
  # ownership and action-slot launch checks (Pages::LaunchChecks). Narrowing
  # and offline pages are not checked. Save re-checks the action slot inside
  # a transaction that holds the owning customer's row lock.
  class VisibilityContract < Reform::Form
    property :audience_admin
    property :audience_member
    property :audience_public
    property :action_key

    validate :at_least_one_audience
    validate :action_key_format
    validate :launched_audiences_stay_submittable

    def deserialize!(params)
      @previous_audiences = model.visible_audiences
      @previous_action_key = model.action_key
      raw = params["visible_audiences"] || params[:visible_audiences]
      selected = PageVisibility::AUDIENCES.select { |audience| Array(raw).map(&:to_s).include?(audience) }
      assigned = {
        "audience_admin" => selected.include?("admin"),
        "audience_member" => selected.include?("member"),
        "audience_public" => selected.include?("public")
      }
      if params.key?("action_key") || params.key?(:action_key)
        assigned["action_key"] = blank_to_nil(params["action_key"] || params[:action_key])
      end
      model.visible_audiences = selected
      model.action_key = assigned.fetch("action_key", model.action_key)
      assigned
    end

    def save
      owner_id = model.customer_id || Authentication::User::PLATFORM_CUSTOMER_ID
      Customer.transaction do
        Customer.lock.find(owner_id)
        sync
        if model.launched?
          LaunchChecks.new(model).action_errors(model.visible_audiences).each do |message|
            errors.add(:base, message)
          end
          return false if errors.any?
        end
        super
      end
    end

    private

    def at_least_one_audience
      return if proposed_audiences.any?

      errors.add(:base, I18n.t("maint_core.errors.validations.page_audiences_blank"))
    end

    def action_key_format
      return if action_key.blank?
      return if action_key.to_s.match?(PageVisibility::ACTION_KEY)

      errors.add(:action_key, I18n.t("maint_core.errors.validations.page_action_key_invalid"))
    end

    def launched_audiences_stay_submittable
      return unless model.launched?

      added = proposed_audiences - Array(@previous_audiences)
      key_changed = action_key != @previous_action_key
      return if added.empty? && !key_changed

      checks = LaunchChecks.new(model)
      messages = []
      if added.any?
        messages.concat(checks.reference_errors(added))
        messages.concat(checks.required_field_errors(added))
        messages.concat(checks.audience_errors(added))
      end
      slot_audiences = key_changed ? proposed_audiences : added
      messages.concat(checks.action_errors(slot_audiences)) if slot_audiences.any?
      messages.each { |message| errors.add(:base, message) }
    end

    def proposed_audiences
      PageVisibility::AUDIENCES.select { |audience| public_send("audience_#{audience}") }
    end

    def blank_to_nil(value)
      value.presence
    end
  end
end
