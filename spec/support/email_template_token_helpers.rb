# frozen_string_literal: true

module EmailTemplateTokenHelpers
  def platform_token_uuid(key)
    k = key.to_s
    token = Emails::TemplateToken.platform.find_by(source_key: k) ||
            Emails::TemplateToken.platform.find_by(source_key: "authentication_user.#{k}") ||
            Emails::TemplateToken.find_or_create_by!(
              customer_id: nil,
              source_type: Emails::TemplateToken::SOURCE_PLATFORM,
              source_key: k.include?(".") ? k : "authentication_user.#{k}"
            ) { |t| t.label = k }
    token.uuid
  end

  def platform_token(key)
    "{{#{platform_token_uuid(key)}}}"
  end
end

RSpec.configure do |config|
  config.include EmailTemplateTokenHelpers
end
