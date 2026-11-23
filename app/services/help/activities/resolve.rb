# frozen_string_literal: true

module Help
  module Activities
    class Resolve
      def self.call(request:)
        request.with_lock do
          if request.resolved?
            Help::Result.new(
              success?: false, model: request, errors: { base: [ I18n.t("help.errors.resolved") ] },
              messages: [ I18n.t("help.errors.resolved") ]
            )
          else
            request.update!(status: "resolved")
            Help::Result.new(success?: true, model: request, errors: {}, messages: [])
          end
        end
      end
    end
  end
end
