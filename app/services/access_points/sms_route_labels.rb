# frozen_string_literal: true

module AccessPoints
  # Shared presentation keys for the route catalog and permissions editor.
  # The containing SMS group supplies the subsystem name; resource suffixes
  # distinguish the controllers without repeating it or changing grant subjects.
  class SmsRouteLabels
    PREFIX = "admin/modules/sms/"
    KEYS = {
      "contacts" => "sms_campaign_http.navigation.contacts",
      "consent_events" => "settings_people.grant_resources.sms_consent_events",
      "entity_syncs" => "settings_people.grant_resources.sms_entity_syncs",
      "segments" => "sms_campaign_http.navigation.segments",
      "campaigns" => "sms_campaign_http.navigation.campaigns",
      "campaign_launches" => "settings_people.grant_resources.sms_campaign_launches",
      "campaign_cancellations" => "settings_people.grant_resources.send_activity_cancellations",
      "campaign_reports" => "settings_people.grant_resources.sms_campaign_reports"
    }.freeze

    def self.key_for(controller_path)
      path = controller_path.to_s
      KEYS[path.delete_prefix(PREFIX)] if path.start_with?(PREFIX)
    end
  end
end
