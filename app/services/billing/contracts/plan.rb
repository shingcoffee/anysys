# frozen_string_literal: true

require "reform/form"

module Billing
  module Contracts
    # Validates platform CRUD inputs for a billing plan.
    class Plan < Reform::Form
      property :code
      property :name
      property :description
      # Amounts are entered in whole currency units (dollars / yuan); the model
      # accessors convert to/from the cents columns.
      property :amount_usd
      property :amount_cny
      property :interval
      property :trial_days
      property :active
      property :is_default
      property :position
      property :limits, virtual: true

      validates :code,        presence: true
      validates :name,        presence: true
      validates :amount_usd,  numericality: { greater_than_or_equal_to: 0 }
      validates :amount_cny,  numericality: { greater_than_or_equal_to: 0 }
      validates :interval,    inclusion: { in: Billing::Plan::INTERVALS }
      validates :trial_days,       numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
      validates :position,         numericality: { only_integer: true }, allow_nil: true
      validate :catalog_identity
      validate :valid_limits
      validate :valid_default
      validate :minor_unit_precision

      def initialize(model, **options)
        super
        self.limits = model.is_a?(Billing::Plan) ? model.plan_limits.to_h { |limit| [limit.item_key, limit.limit_value] } : {}
      end

      def normalized_limits
        limits.to_h.transform_keys(&:to_s).transform_values { |raw| Billing::AssignPlanLimits.parse(raw) }
      end

      private

      def catalog_identity
        return unless model.is_a?(Billing::Plan)
        duplicate = Billing::Plan.where(code: code).where.not(id: model.id).exists?
        errors.add(:code, :taken) if duplicate
        return unless model.persisted?

        errors.add(:code, I18n.t("admin_settings.errors.validations.code_immutable")) if code != model.code
        if model.referenced?
          %i[amount_usd amount_cny interval].each do |key|
            different = key == :interval ? public_send(key) != model.interval : public_send(key).to_s.to_d != model.public_send(key)
            errors.add(key, I18n.t("admin_settings.errors.validations.catalog_terms_immutable")) if different
          end
        end
      end

      def valid_limits
        unless limits.respond_to?(:to_h)
          errors.add(:limits, I18n.t("admin_settings.errors.validations.limit_invalid"))
          return
        end
        limits.to_h.each do |key, raw|
          if !Billing::AssignPlanLimits.allowed_key?(key) || !Billing::AssignPlanLimits.valid?(raw)
            errors.add(:limits, I18n.t("admin_settings.errors.validations.limit_invalid"))
          end
        end
      end

      def valid_default
        boolean = ::ActiveModel::Type::Boolean.new
        return unless boolean.cast(is_default)
        unless boolean.cast(active) && amount_usd.to_s.to_d.zero? && amount_cny.to_s.to_d.zero? && trial_days.to_i.zero? && model.try(:archived_at).nil?
          errors.add(:is_default, I18n.t("admin_settings.errors.validations.default_plan_must_be_free"))
        end
        return if errors[:limits].present?
        map = normalized_limits
        if Billing::Countable::Registry.keys.any? { |key| !map.key?(key) || map[key].negative? }
          errors.add(:limits, I18n.t("admin_settings.errors.validations.free_limits_required"))
        end
      end

      def minor_unit_precision
        %i[amount_usd amount_cny].each do |key|
          value = public_send(key).to_s.to_d
          errors.add(key, :invalid) unless value == value.round(2)
        end
      end
    end
  end
end
