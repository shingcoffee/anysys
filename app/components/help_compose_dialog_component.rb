# frozen_string_literal: true

class HelpComposeDialogComponent < ApplicationComponent
  KINDS = {
    notify: {
      form_name: :support_ticket,
      files_param: :images,
      dialog_target: "notifyDialog"
    },
    email: {
      form_name: :help_email,
      files_param: :attachments,
      dialog_target: "emailDialog"
    }
  }.freeze

  def initialize(kind:, action:)
    @kind = kind.to_sym
    @action = action
    @config = KINDS.fetch(@kind)
  end

  attr_reader :kind, :action

  def form_name = @config[:form_name]
  def files_param = @config[:files_param]
  def dialog_target = @config[:dialog_target]

  def accept
    kind == :email ? Help::AttachmentRules.email_accept : Help::AttachmentRules.image_accept
  end

  def title = I18n.t("#{i18n_prefix}.title")
  def submit_label = I18n.t("#{i18n_prefix}.send")
  def cancel_label = I18n.t("#{i18n_prefix}.cancel")
  def subject_label = I18n.t("#{i18n_prefix}.subject")
  def message_label = I18n.t("#{i18n_prefix}.message")
  def files_label = I18n.t("#{i18n_prefix}.#{files_param}")
  def files_hint = I18n.t("#{i18n_prefix}.#{files_param}_hint")
  def helper_text
    I18n.t("#{i18n_prefix}.helper")
  end

  def subject_placeholder
    I18n.t("#{i18n_prefix}.subject_placeholder")
  end

  def message_placeholder
    I18n.t("#{i18n_prefix}.message_placeholder")
  end

  def title_id = "help-#{kind}-title"
  def subject_id = "help-#{kind}-subject"
  def body_id = "help-#{kind}-body"
  def files_id = "help-#{kind}-files"

  def field_name(key)
    "#{form_name}[#{key}]"
  end

  def files_field_name
    "#{form_name}[#{files_param}][]"
  end

  def stimulus_data
    Help::AttachmentRules.stimulus_data(accept: accept)
  end

  private

  def i18n_prefix
    "chrome.help_menu.#{kind}"
  end
end
