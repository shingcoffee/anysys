# frozen_string_literal: true

# A guided sequence of pages for one customer, built by the platform owner
# inside one of the customer's domains. Steps point at page action keys, so
# each audience gets its own page.
class Journey < ApplicationRecord
  include JsonSerializable

  AUDIENCES = PageVisibility::AUDIENCES

  belongs_to :customer
  belongs_to :entity_domain
  has_many :runs, class_name: "JourneyRun", dependent: :delete_all

  enum :status, { draft: 0, launched: 1 }, default: :draft
  json_attribute :definition, default: {}

  validates :name, presence: true, length: { maximum: 120 }
  validates :key, format: { with: PageVisibility::ACTION_KEY }, uniqueness: { scope: :customer_id }
  validate :audience_present

  scope :for_customer, ->(customer_id) { where(customer_id: customer_id) }
  scope :by_name, -> { order(Arel.sql("LOWER(journeys.name)"), :id) }
  scope :starting_on, ->(action_key) { where("json_extract(journeys.definition, '$.steps[0].action_key') = ?", action_key.to_s) }
  # Started from an existing record of the entity (a record start step);
  # `action_key` narrows to the page the journey opens first.
  scope :starting_from_record, ->(entity_id, action_key = nil) {
    scope = where("json_extract(journeys.definition, '$.steps[0].kind') = 'record'")
            .where("CAST(json_extract(journeys.definition, '$.steps[0].entity_id') AS TEXT) = ?", entity_id.to_s)
    action_key ? scope.where("json_extract(journeys.definition, '$.steps[1].action_key') = ?", action_key.to_s) : scope
  }
  # Opens by creating a user account, then saves the person record on `action_key`'s page.
  scope :opening_with_user_on, ->(action_key) {
    where("json_extract(journeys.definition, '$.steps[0].kind') = 'user'")
      .where("json_extract(journeys.definition, '$.steps[1].action_key') = ?", action_key.to_s)
  }
  scope :for_any_audience, ->(audiences) {
    columns = AUDIENCES & Array(audiences).map(&:to_s)
    columns.empty? ? none : where(columns.map { |audience| arel_table["audience_#{audience}"].eq(true) }.reduce(:or))
  }

  def steps_definition = Journeys::Definition.new(definition_json)

  def visible_audiences = AUDIENCES.select { |audience| public_send("audience_#{audience}") }
  def visible_to?(audience) = visible_audiences.include?(audience.to_s)

  def visible_audiences=(list)
    selected = Array(list).map(&:to_s)
    AUDIENCES.each { |audience| public_send("audience_#{audience}=", selected.include?(audience)) }
  end

  private

  def audience_present
    errors.add(:base, I18n.t("journeys.launch.errors.audiences_blank")) if visible_audiences.empty?
  end
end
