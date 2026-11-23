# frozen_string_literal: true

module Dashboard
  class ModuleCards
    KNOWN = {
      "authentication" => {
        primary_path: ->(cid) { "/#{cid}/admin/modules/authentication/users" },
        primary_label_key: "feature_modules.authentication.entries.users",
        secondaries: [
          {
            path: ->(cid) { "/#{cid}/admin/modules/authentication/events" },
            label_key: "feature_modules.authentication.entries.events"
          }
        ]
      },
      "email" => {
        primary_path: ->(cid) { "/#{cid}/admin/modules/emails/templates" },
        primary_label_key: "feature_modules.email.titles.templates",
        secondaries: [
          {
            path: ->(cid) { "/#{cid}/admin/modules/emails/send_activities" },
            label_key: "feature_modules.email.titles.send_activities"
          },
          {
            path: ->(cid) { "/#{cid}/admin/modules/emails/lists" },
            label_key: "feature_modules.email.entries.audience"
          }
        ]
      },
      "payment" => {
        primary_path: ->(cid) { "/#{cid}/admin/modules/payments/transactions" },
        primary_label_key: "feature_modules.payment.entries.transactions",
        secondaries: [
          {
            path: ->(cid) { "/#{cid}/admin/modules/payments/reconciliations" },
            label_key: "feature_modules.payment.entries.reconciliations"
          }
        ]
      },
      "sms" => {
        primary_path: ->(cid) { "/#{cid}/admin/modules/sms/campaigns" },
        primary_label_key: "sms_campaign_http.navigation.campaigns",
        secondaries: [
          {
            path: ->(cid) { "/#{cid}/admin/modules/sms/contacts" },
            label_key: "feature_modules.email.entries.audience"
          },
          {
            path: ->(cid) { "/#{cid}/admin/modules/sms/messages" },
            label_key: "feature_modules.sms.entries.messages"
          }
        ]
      },
      "captcha" => {
        secondaries: []
      },
      "ai_assistant" => {
        primary_path: ->(cid) { "/#{cid}/admin/assistant" },
        primary_label_key: "admin_misc.dashboard.modules.open_assistant",
        secondaries: []
      },
      "website" => {
        primary_path: ->(cid) { "/#{cid}/admin/modules/website" },
        primary_label_key: "feature_modules.website.entries.pages",
        secondaries: []
      }
    }.freeze

    def self.call(customer:)
      new(customer).call
    end

    def self.blurb_for(fm)
      key = "admin_misc.dashboard.modules.blurbs.#{fm.key}"
      return I18n.t(key) if I18n.exists?(key)

      I18n.t("admin_misc.dashboard.modules.blurbs.fallback", name: fm.display_name)
    end

    def initialize(customer)
      @customer = customer
    end

    def call
      FeatureModules::Module.available_for_customer(@customer.id).by_name.map { |fm| card_for(fm) }
    end

    private

    def card_for(fm)
      spec = KNOWN[fm.key]
      primary, secondaries, links =
        spec ? known_links(spec) : fallback_links(fm)
      ModuleCard.new(
        key: fm.key,
        name: fm.display_name,
        description: self.class.blurb_for(fm),
        primary: primary,
        secondaries: secondaries,
        links: links,
        section: FeatureModules::NavigationOrder.section_for(fm.key)
      )
    end

    def known_links(spec)
      cid = @customer.id
      primary = if spec[:primary_path]
        Link.new(label: I18n.t(spec[:primary_label_key]), href: spec[:primary_path].call(cid))
      end
      secondaries = spec.fetch(:secondaries).map do |item|
        Link.new(label: I18n.t(item[:label_key]), href: item[:path].call(cid))
      end
      [primary, secondaries, [primary, *secondaries].compact]
    end

    def fallback_links(fm)
      context = DashboardContext.new(
        current_user: nil,
        current_customer: @customer,
        current_menu_item: :modules,
        request_path: "/"
      )
      contributions = fm.registration_class.sidebar_contributions(context)
      entries = links_from(contributions[:entries], menu_item: :modules, module_key: fm.key)
      [entries.first, entries.drop(1).first(2), entries]
    end

    def links_from(contributions, menu_item:, module_key:)
      Array(contributions).flat_map do |contribution|
        if contribution.children.any?
          links_from(contribution.children, menu_item: menu_item, module_key: module_key)
        else
          href = contribution.href_for(customer_id: @customer.id, menu_item: menu_item, module_key: module_key)
          href.present? ? [Link.new(label: contribution.label, href: href)] : []
        end
      end
    end
  end
end
