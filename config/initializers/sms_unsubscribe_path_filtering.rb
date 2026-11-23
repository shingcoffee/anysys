# frozen_string_literal: true

require "action_dispatch/http/request"
require "action_dispatch/journey/router/utils"

# Rails::Rack::Logger and ActionController::Instrumentation both use this
# display-only API. Parameter filters alone cannot redact a capability embedded
# in PATH_INFO. Match with the same normalization the Rails router uses, including
# trailing/repeated slashes, without changing the real path or signed token.
module SmsUnsubscribePathFiltering
  UNSUBSCRIBE_PATH = %r{\A/sms/unsubscribes/[^/]+\z}.freeze

  def filtered_path
    normalized_path = ActionDispatch::Journey::Router::Utils.normalize_path(path_info)
    return super unless UNSUBSCRIBE_PATH.match?(normalized_path)

    # `super` may have cached the pre-router spelling of the path. Replace its
    # whole display path rather than matching the now-normalized real path;
    # Rails' already-filtered query suffix is left untouched.
    super.sub(/\A[^?]+/) { "#{script_name}/sms/unsubscribes/#{ActiveSupport::ParameterFilter::FILTERED}" }
  end
end

ActionDispatch::Request.prepend(SmsUnsubscribePathFiltering)
