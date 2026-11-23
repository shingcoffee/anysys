# frozen_string_literal: true

module Authentication
  # I18n adapter over Mailers::ShellComponent for the transactional auth
  # emails. Confirmation, passwordless sign-in, and reset-password share
  # the same card; only the copy scope and action URL change.
  class MailerShellComponent < ApplicationComponent
    COPY_KEYS = %i[preheader brand heading title instructions action fallback ignore footer].freeze

    # @param scope [Symbol, String] copy scope under `auth.mailer.*`
    # @param email [String] recipient address, interpolated into the greeting
    # @param action_url [String] absolute URL behind both the button and the
    #   plain-text fallback link
    def initialize(scope:, email:, action_url:)
      @scope = scope
      @email = email
      @action_url = action_url
    end

    attr_reader :action_url

    COPY_KEYS.each { |key| define_method(key) { copy(key) } }

    def greeting
      copy(:greeting, email: @email)
    end

    def call
      render Mailers::ShellComponent.new(
        preheader: preheader,
        brand: brand,
        heading: heading,
        title: title,
        greeting: greeting,
        body: instructions,
        action: action,
        action_url: action_url,
        fallback: fallback,
        note: optional_copy(:note),
        ignore: ignore,
        footer: footer
      )
    end

    private

    def copy(key, **options)
      I18n.t("auth.mailer.#{@scope}.#{key}", **options)
    end

    def optional_copy(key)
      i18n_key = "auth.mailer.#{@scope}.#{key}"
      copy(key) if I18n.exists?(i18n_key)
    end
  end
end
