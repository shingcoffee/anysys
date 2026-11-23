# frozen_string_literal: true

# A visitor's walk through a Journey's steps, or (without a journey) the
# carrier of a refused submit's typed values and of records pinned into one
# page's locked inputs (a record page opening a link's page with the record
# locked in, Entities::AssociationPages). Only a SHA-256 digest of the
# token is stored, and an anonymous run is also pinned to the browser session
# that started it. A run stops once its journey is taken offline; the
# platform owner may still walk a draft they preview.
class JourneyRun < ApplicationRecord
  include JsonSerializable

  EXPIRES_IN = 3.days
  SESSION_KEY = :journey_runs
  SESSION_LIMIT = 10
  RECORDS_PER_STEP = 50
  PINNED = "pinned"
  SKIPPED = "skipped"

  belongs_to :customer
  belongs_to :user, class_name: "Authentication::User", optional: true
  belongs_to :journey, optional: true

  enum :status, { active: 0, completed: 1 }, default: :active
  json_attribute :state, default: {}

  validate :journey_belongs_to_customer

  scope :usable, -> { active.where("expires_at > ?", Time.current) }

  def self.digest_for(raw) = Digest::SHA256.hexdigest(raw.to_s)

  def self.issue!(customer_id:, user:, session:, state: {}, **attributes)
    raw = SecureRandom.urlsafe_base64(32)
    run = create!(customer_id: customer_id, user_id: user&.id, token_digest: digest_for(raw),
                  state: state.to_json, expires_at: EXPIRES_IN.from_now, **attributes)
    session[SESSION_KEY] = (Array(session[SESSION_KEY]) + [run.token_digest]).last(SESSION_LIMIT) unless user
    [run, raw]
  end

  # A run without a journey whose +inputs+ (field slug => record id) fill
  # +page+'s locked inputs; Pages::InputBindings still re-checks each record.
  def self.pin!(customer_id:, user:, session:, page:, inputs:)
    issue!(customer_id: customer_id, user: user, session: session,
           state: { PINNED => { "page_id" => page.id.to_s, "inputs" => inputs.to_h.transform_values(&:to_s) } })
  end

  def self.find_usable(token:, customer_id:, user:, session:)
    return unless token.is_a?(String) && token.length.between?(20, 100)

    run = usable.find_by(customer_id: customer_id, token_digest: digest_for(token))
    return unless run

    owned = run.user_id ? run.user_id == user&.id : Array(session[SESSION_KEY]).include?(run.token_digest)
    run if owned && run.walkable_by?(user)
  end

  def walkable_by?(user)
    journey.nil? || journey.launched? || JourneyVisibility.allowed?(user)
  end

  def records
    records = state_json.is_a?(Hash) ? state_json["records"] : nil
    records.is_a?(Hash) ? records : {}
  end

  # Readers only take a step's latest record, so a repeating step keeps just
  # its most recent RECORDS_PER_STEP ids.
  def record!(step_key, id)
    data = state_json.is_a?(Hash) ? state_json : {}
    ids = (Array(records[step_key.to_s]) + [id.to_s]).uniq.last(RECORDS_PER_STEP)
    data["records"] = records.merge(step_key.to_s => ids)
    update!(state: data.to_json)
  end

  # Later steps an earlier step's processing left out (Journeys::Advance).
  def skipped
    list = state_json.is_a?(Hash) ? state_json[SKIPPED] : nil
    list.is_a?(Array) ? list.map(&:to_s) : []
  end

  def skip!(step_keys)
    added = Array(step_keys).map(&:to_s) - skipped
    return if added.empty?

    data = state_json.is_a?(Hash) ? state_json : {}
    data[SKIPPED] = skipped + added
    update!(state: data.to_json)
  end

  def bindings_for(page)
    return pinned_inputs(page) unless journey

    step = journey.steps_definition.step(current_step)
    return {} unless step && step.action_key == page.action_key

    step.inputs.each_with_object({}) do |(field, from), bound|
      id = Array(records[from]).last
      bound[field] = id if id.present?
    end
  end

  private

  def pinned_inputs(page)
    pinned = state_json.is_a?(Hash) ? state_json[PINNED] : nil
    return {} unless pinned.is_a?(Hash) && pinned["page_id"] == page.id.to_s && pinned["inputs"].is_a?(Hash)

    pinned["inputs"].transform_values(&:to_s)
  end

  def journey_belongs_to_customer
    errors.add(:journey, :invalid) if journey && journey.customer_id != customer_id
  end
end
