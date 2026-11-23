# frozen_string_literal: true

module FlowchartRuntime
  # Tenant-scoped in-app notification writer for create_notification.
  # Recipients must belong to ctx[:customer_id]; pages must be launched and
  # either owned by that customer or shared.
  module Notifications
    class Error < StandardError; end

    module_function

    def create(ctx, recipient:, title:, body:, page_id: nil)
      customer_id = ctx && ctx[:customer_id]
      raise Error, "customer_id is required" if customer_id.blank?

      ids = Array(recipient).flatten.filter_map { |id| Integer(id, exception: false) }.uniq
      users = ids.map { |id| ::Authentication::User.find_by(id: id, customer_id: customer_id) }
      return Step.fail(ctx, :"create_notification.recipient_not_found") if users.empty? || users.any?(&:nil?)

      resolved_page = resolve_page_id(customer_id, page_id)
      return Step.fail(ctx, :"create_notification.page_not_found") if page_id.present? && resolved_page.nil?

      title_value = stringify(title)
      body_value = stringify(body)
      users.each do |user|
        FlowchartNotification.create!(
          customer_id: customer_id,
          user_id: user.id,
          title: title_value,
          body: body_value,
          page_id: resolved_page
        )
      end
      true
    end

    def stringify(value)
      (value || {}).to_h.stringify_keys
    end

    def resolve_page_id(customer_id, page_id)
      return nil if page_id.blank?

      Page.launched.where(id: page_id, customer_id: [customer_id, nil]).pick(:id)
    end
    private_class_method :stringify, :resolve_page_id
  end
end
