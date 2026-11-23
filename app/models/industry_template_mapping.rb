# frozen_string_literal: true

class IndustryTemplateMapping < ApplicationRecord
  validates :industry, presence: true
  validates :template_key, presence: true, uniqueness: { scope: :industry }
  validate :industry_must_be_valid
  validate :template_key_must_exist

  scope :for_industry, ->(industry) { where(industry: industry.to_s) }
  scope :for_template, ->(template_key) { where(template_key: template_key.to_s) }

  def self.template_keys_for(industry)
    for_industry(industry).pluck(:template_key)
  end

  def self.industries_for(template_key)
    for_template(template_key).pluck(:industry)
  end

  def self.replace_for_industry!(industry, template_keys)
    transaction do
      for_industry(industry).delete_all
      template_keys.each do |key|
        create!(industry: industry.to_s, template_key: key.to_s)
      end
    end
  end

  private

  def industry_must_be_valid
    return if industry.blank?

    errors.add(:industry, I18n.t("maint_platform.errors.validations.invalid_industry")) unless Customer.industries.key?(industry)
  end

  def template_key_must_exist
    return if template_key.blank?

    errors.add(:template_key, I18n.t("maint_platform.errors.validations.invalid_template")) unless PageLayoutTemplates.find(template_key)
  end
end
