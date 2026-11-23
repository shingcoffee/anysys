# frozen_string_literal: true

module Emails
  class Template < ApplicationRecord
    self.table_name = "email_templates"

    include TenantScoped
    include Versionable

    EDITOR_TYPES = %w[rich_text code].freeze
    STATUSES     = %w[draft active retired].freeze

    has_rich_text :body

    has_many :email_messages, dependent: :restrict_with_exception,
                              class_name: "Emails::Message",
                              foreign_key: :email_template_id

    acts_as_versionable reflection: :template_versions,
                        version_class: "Emails::TemplateVersion",
                        content_class: "Emails::TemplateContent",
                        foreign_key: :email_template_id,
                        snapshot: :definition_snapshot

    before_validation :sync_body_html!
    before_validation :normalize_tokens!

    validates :customer_id, presence: true
    validates :name,        presence: true
    validates :subject,     presence: true
    validates :body_html,   presence: true
    validates :editor_type, inclusion: { in: EDITOR_TYPES }
    validates :status,      inclusion: { in: STATUSES }
    validate :content_locked_during_send

    scope :active, -> { where(status: "active") }

    def active? = status == "active"

    # Subject, body, and editor stay put while a send is still rendering this
    # template. A rename does not change what recipients receive.
    def content_locked_during_send
      return unless persisted? && in_use_by_non_terminal_send_activity? && authored_content_changed?

      errors.add(:base, I18n.t("admin_modules.emails.templates.errors.content_locked"))
    end

    def in_use_by_non_terminal_send_activity?
      Emails::SendActivities::SendActivity
        .where(customer_id: customer_id, email_template_id: id,
               status: Emails::SendActivities::SendActivity::NON_TERMINAL_STATUSES)
        .exists?
    end

    def update_status!(new_status)
      new_status = new_status.to_s
      unless STATUSES.include?(new_status)
        errors.add(:status, I18n.t("admin_modules.emails.templates.status.invalid"))
        return false
      end

      if %w[draft retired].include?(new_status) && in_use_by_non_terminal_send_activity?
        errors.add(:status, I18n.t("admin_modules.emails.templates.status.in_use"))
        return false
      end

      update(status: new_status)
    end

    # Sync email-ready HTML from ActionText for rich_text templates.
    # Used by before_validation and by unsaved preview/test_send so all paths
    # share one compiler. Code templates author body_html directly — no-op.
    # A cleared rich_text body syncs to "" so stale HTML cannot linger.
    def sync_body_html!
      return self unless editor_type == "rich_text"

      self.body_html = body.present? ? Emails::CompileTemplate.call(self) : ""
      self
    end

    def authored_content_changed?
      will_save_change_to_subject? || will_save_change_to_body_text? || will_save_change_to_editor_type? ||
        (editor_type == "code" && will_save_change_to_body_html?) ||
        (editor_type == "rich_text" && rich_text_body_changed?)
    end

    def rich_text_body_changed?
      rich_text_body&.has_changes_to_save?
    end

    # Ensure subject / plain text / code HTML persist UUID tokens only
    # (never chip markup or human-readable {{Label}} display forms).
    def normalize_tokens!
      self.subject = Emails::TemplateTokenCodec.normalize_for_storage(subject, customer_id: customer_id) if subject.present?
      self.body_text = Emails::TemplateTokenCodec.normalize_for_storage(body_text, customer_id: customer_id) if body_text.present?
      if body_html.present?
        self.body_html = Emails::TemplateTokenCodec.normalize_for_storage(body_html, customer_id: customer_id, format: :html)
      end
    end

    # Versionable snapshot reader: the JSON payload committed on every save.
    # #to_trix_html (not #to_s) is used for rich_text bodies: #to_s renders
    # through the full layout partial, wrapping the fragment in a
    # `trix-content` div plus HTML comment annotations, which would nest
    # deeper every time a version got restored and re-saved.
    def definition_snapshot
      {
        "subject"     => subject,
        "body_html"   => body_html,
        "body_text"   => body_text,
        "editor_type" => editor_type,
        "body_raw"    => (editor_type == "rich_text" ? body.to_trix_html.to_s : body_html.to_s)
      }.to_json
    end

    # Both head-switch paths must commit the head, scalar columns and ActionText
    # together. The shared Versionable hook also keeps reads in sync with head.
    def restore_as_new!(version)
      version = current_line_versions.find(version.id)
      transaction { super(version) }
    end

    def set_current_version!(version)
      version = current_line_versions.find(version.id)
      transaction { super(version) }
    end

    def reload_definition_from_head!
      payload = resolved_current_version&.payload_json
      transaction { apply_definition_payload!(payload) } if payload.present?
    end

    private

    # Bypass Template's autocommit when applying an existing snapshot. Assigning
    # through `self.body=` on an unchanged persisted template can autosave the
    # parent; write the ActionText association directly to avoid a second head.
    def apply_definition_payload!(payload)
      return if payload.blank?

      attributes = {
        subject:     payload["subject"].to_s,
        body_html:   payload["body_html"].to_s,
        body_text:   payload["body_text"],
        editor_type: payload["editor_type"].presence || self.class.column_defaults.fetch("editor_type")
      }
      update_columns(attributes) if attributes.any? { |key, value| public_send(key) != value }
      return unless editor_type == "rich_text"

      raw = payload["body_raw"].to_s
      rich_text = rich_text_body || build_rich_text_body
      return if rich_text.persisted? && rich_text.body&.to_trix_html.to_s == raw

      rich_text.body = raw
      rich_text.save!
    end
  end
end
