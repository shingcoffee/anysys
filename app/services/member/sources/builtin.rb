# frozen_string_literal: true

require_relative "builtin_surface"

module Member
  module Sources
    class Builtin < Member::SurfaceSource
      def self.key         ; :builtin ; end
      def self.name        ; I18n.t("admin_settings.member.sources.builtin.name") ; end
      def self.description ; I18n.t("admin_settings.member.sources.builtin.description") ; end
      def self.editable?   ; false ; end
      def self.position    ; 0 ; end

      ENTRIES = [
        { key: :builtin_home,     label_key: "chrome.menu_bar.items.home", icon: :home, path_seg: "", default_position:  0 },
        { key: :builtin_profile,  label_key: "member.common.profile",  icon: :user,         path_seg: "profile",  default_position: 10 },
        { key: :builtin_security, label_key: "member.common.security", icon: :shield_check, path_seg: "security", default_position: 20 }
      ].freeze

      def surfaces
        ENTRIES.map { |e|
          BuiltinSurface.new(
            key: e[:key], label: I18n.t(e[:label_key]), icon: e[:icon],
            path_seg: e[:path_seg], default_position: e[:default_position]
          )
        }
      end

      register!
    end
  end
end
