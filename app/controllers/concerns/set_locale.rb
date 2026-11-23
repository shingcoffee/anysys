# frozen_string_literal: true

# SetLocale
#
# Resolves the active UI locale for every request and applies it for the
# duration of the action (reset afterwards via around_action). Priority order,
# first hit wins:
#
#   1. params[:locale]        — explicit switch (must be an available locale)
#   2. current_user.locale    — persisted per-user preference (signed-in users)
#   3. cookies[:locale]       — anonymous / pre-sign-in preference
#   4. Current.customer.locale — tenant default (set by the platform owner per
#      customer). A fallback, not a mandate: any explicit personal choice above
#      wins, but the tenant default beats a mere browser guess.
#   5. Accept-Language header  — best match among available locales
#   6. I18n.default_locale    — :en
#
# The tenant tier sits BELOW the personal signals (params/user/cookie) so a user
# can always override their customer's default via the switcher, yet ABOVE
# Accept-Language so a fresh user with no stored choice lands in the tenant's
# language rather than a browser guess. Outside any tenant (public / platform
# pages where Current.customer is nil) the chain simply skips this tier.
#
# Only locales in I18n.available_locales are ever honoured; anything else is
# ignored so a hand-crafted `?locale=xx` can never render an undefined locale.
module SetLocale
  extend ActiveSupport::Concern

  included do
    around_action :switch_locale
    helper_method :current_locale
  end

  private

  def switch_locale(&action)
    I18n.with_locale(resolved_locale, &action)
  end

  # The locale in effect for this request (available in views as current_locale).
  def current_locale
    @current_locale ||= resolved_locale
  end

  def resolved_locale
    from_params ||
      from_current_user ||
      from_cookie ||
      from_customer ||
      from_header ||
      I18n.default_locale
  end

  # Tenant default locale — a fallback beneath the personal signals: it fills in
  # for a user who has made no explicit choice, but never overrides one. nil (no
  # tenant, or no default configured) skips this tier.
  def from_customer
    available(Current.customer&.locale)
  end

  def from_params
    available(params[:locale])
  end

  def from_current_user
    return unless respond_to?(:current_user)

    available(current_user&.locale)
  end

  def from_cookie
    available(cookies[:locale])
  end

  # http_accept_language returns the best match (a String) or nil.
  def from_header
    return unless request.env["HTTP_ACCEPT_LANGUAGE"]

    match = http_accept_language.compatible_language_from(I18n.available_locales)
    available(match)
  end

  # Coerce an arbitrary value to a supported locale symbol, or nil.
  def available(value)
    return if value.blank?

    sym = value.to_s.to_sym
    sym if I18n.available_locales.include?(sym)
  end
end
