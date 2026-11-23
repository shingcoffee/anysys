# frozen_string_literal: true

# LocalesController
#
# Single endpoint that switches the UI language. Public (no tenant scope, no
# auth): anonymous visitors on public pages may switch too. When a user is
# signed in the choice is persisted to their profile so it follows them across
# devices; a cookie is always written so anonymous/pre-sign-in choices stick.
#
# Only locales in I18n.available_locales are accepted — an unknown value is
# ignored and the redirect still happens (idempotent, never errors).
class LocalesController < ApplicationController
  def update
    locale = requested_locale

    if locale
      cookies[:locale] = { value: locale.to_s, expires: 1.year, same_site: :lax }
      current_user&.update_column(:locale, locale.to_s) if user_signed_in?
    end

    redirect_to locale_redirect_location(locale), allow_other_host: false
  end

  private

  def requested_locale
    value = params[:locale].to_s.to_sym
    value if I18n.available_locales.include?(value)
  end

  def locale_redirect_location(locale)
    return root_path if request.referer.blank? || request.referer.start_with?("//")

    referer = URI.parse(request.referer.to_s)
    return root_path unless same_origin_referer?(referer)

    # Flat parsing preserves repeated values and nested query keys verbatim.
    query = Rack::Utils.parse_query(referer.query)
    if locale && query.key?("locale")
      query["locale"] = locale.to_s
      referer.query = Rack::Utils.build_query(query)
    end

    referer.to_s
  rescue URI::InvalidURIError, ArgumentError
    root_path
  end

  def same_origin_referer?(referer)
    if referer.host
      referer.is_a?(URI::HTTP) && referer.scheme == request.scheme &&
        referer.host == request.host && referer.port == request.port && referer.userinfo.nil?
    else
      referer.scheme.nil? && referer.path.start_with?("/")
    end
  end
end
