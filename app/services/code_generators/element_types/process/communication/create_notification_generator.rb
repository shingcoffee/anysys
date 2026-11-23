# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Communication
        class CreateNotificationGenerator < BaseGenerator
          generator_metadata do
            description "Creates an in-app notification for one or more users of this customer. Use send_email to send mail, and load_current_user when you need the signed-in user's email or role first. recipient is a Ruby expression for a user id (default ctx[:current_user_id]); recipients lists extra ctx paths of user ids. title and body are localized hashes stored as written. page is an optional launched same-customer or shared page stored as the link. Writes one row per distinct same-tenant user. Fails as recipient_not_found when any id is missing or foreign, page_not_found when page is set but not launched, or create_notification.failed when customer_id is missing."
            category :communication
            version "1.2.0"
            presentation icon: "M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9",
                        color: "amber", single_use: false, privileged: false
          end

          config_schema do
            expression :recipient, default: "ctx[:current_user_id]", example: "ctx[:current_user_id]",
                       description: "Ruby expression for a user id of this customer, or an array of ids. Default ctx[:current_user_id] is the signed-in account, not a person record id."
            list :recipients, item: :input, default: [], group: :advanced,
                 description: "Extra ctx paths of user ids to notify, such as admin_id or owner.id. Combined with recipient; duplicates are notified once."
            localized_text :title, required: true, example: { "en" => "Notice" },
                           description: "Localized notification title as {\"en\" => \"Order received\", \"zh-CN\" => \"...\"}. Stored as written; it is not interpolated."
            localized_text :body, required: true, example: { "en" => "Your request was received." },
                           description: "Localized notification body as a locale-key hash. Stored as written; put any order number in the text yourself."
            reference :page, source: :pages,
                      description: "Optional launched page of this customer, or a shared page, stored as the notification link. A draft, missing, or other-tenant page fails the step."
          end

          def generate_body
            attempt('"create_notification.failed"', FlowchartRuntime::Notifications::Error) do
              ["FlowchartRuntime::Notifications.create(ctx, #{create_args})"]
            end
          end

          private

          def create_args
            args = [
              "recipient: #{recipients_source}",
              "title: #{read(:title)}",
              "body: #{read(:body)}"
            ]
            args << "page_id: #{read(:page)}" unless value(:page).to_s.strip.empty?
            args.join(", ")
          end

          def recipients_source
            items = [read(:recipient)] + Array(value(:recipients)).filter_map { |path| recipient_path_source(path) }
            "[#{items.join(', ')}]"
          end

          def recipient_path_source(path)
            root, *rest = path.to_s.split(".", -1)
            return nil if root.nil? || root.empty?
            return nil unless safe_ident?(root) && rest.all? { |segment| safe_ident?(segment) || segment.match?(/\A\d+\z/) }
            return "ctx[:#{root}]" if rest.empty?

            keys = rest.map { |segment| segment.match?(/\A\d+\z/) ? segment : ":#{segment}" }.join(", ")
            "FlowchartRuntime::Step.dig(ctx[:#{root}], #{keys})"
          end
        end
      end
    end
  end
end
