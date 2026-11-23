# frozen_string_literal: true

module Websites
  module Assistant
    # Takes back what one assistant reply wrote to the website: pages it
    # created are deleted and pages it revised get their previous title, slug,
    # navigation flag and sections back. The reply's metadata carries one entry
    # per page (see .entry) with a fingerprint of the page as the reply left
    # it. A page that no longer matches has been edited since, and the whole
    # undo is refused rather than overwrite that work.
    class Undo
      KEY = "website_undo"
      RESTORED = %w[title slug nav_visible sections].freeze

      Result = Struct.new(:success?, :errors, keyword_init: true)

      class Refused < StandardError
        attr_reader :errors

        def initialize(errors)
          @errors = errors
          super(errors.join(" "))
        end
      end
      private_constant :Refused

      class << self
        def call(message:, customer:)
          new(message: message, customer: customer).call
        end

        # Call under the writer's customer/page locks after loading current
        # state. Keep JSON values detached from later in-memory mutations.
        def snapshot(page)
          RESTORED.to_h { |field| [field, page.public_send(field)] }.merge("page_id" => page.id).deep_dup
        end

        def entry(page, before: nil)
          (before || { "page_id" => page.id, "title" => page.title, "created" => true })
            .merge("fingerprint" => fingerprint(page.reload))
        end

        def fingerprint(page)
          Digest::SHA256.hexdigest(JSON.generate([page.title, page.slug, page.nav_visible, page.home, page.published, page.sections]))
        end

        # nil when the reply wrote nothing to the website.
        def state(message)
          data = message.metadata_json[KEY]
          return nil unless data.is_a?(Hash) && Array(data["pages"]).any?

          data["undone_at"].present? ? :undone : :available
        end
      end

      def initialize(message:, customer:)
        @message = message
        @customer = customer
      end

      def call
        PageShortcuts::Collisions.with_customer_lock(customer_id: @customer.id) do
          @message.class.for_customer(@customer.id).scoping(all_queries: true) { @message.reload(lock: true) }
          @entries = nil
          raise Refused, [t("errors.unavailable")] unless self.class.state(@message) == :available

          pages = current_pages
          conflicts = entries.filter_map { |entry| conflict(entry, pages[entry["page_id"]]) }
          raise Refused, conflicts if conflicts.any?

          entries.reverse_each { |entry| revert!(entry, pages.fetch(entry["page_id"])) }
          mark_undone!
        end
        Result.new(success?: true, errors: [])
      rescue Refused => e
        Result.new(success?: false, errors: e.errors)
      rescue ActiveRecord::RecordNotFound
        Result.new(success?: false, errors: [t("errors.unavailable")])
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::StatementTimeout
        Result.new(success?: false, errors: [t("errors.retry")])
      end

      private

      def entries
        @entries ||= Array(@message.metadata_json.dig(KEY, "pages")).grep(Hash)
      end

      def current_pages
        @website = Website.find_by(customer_id: @customer.id)
        return {} unless @website

        site_pages.where(id: entries.map { |entry| entry["page_id"] }).order(:id).lock.index_by(&:id)
      end

      def site_pages
        @website.pages.where(customer_id: @customer.id)
      end

      def conflict(entry, page)
        return t("errors.missing", title: entry["title"]) if page.nil?
        return t("errors.published", title: page.title) if page.published?
        return t("errors.changed", title: page.title) if self.class.fingerprint(page) != entry["fingerprint"]

        t("errors.home_in_use", title: page.title) if entry["created"] && page.home? && pages_outlive_home?
      end

      # The reply's own new pages go with it; any other page would be left on
      # a site without a home.
      def pages_outlive_home?
        created = entries.select { |entry| entry["created"] }.map { |entry| entry["page_id"] }
        site_pages.where.not(id: created).exists?
      end

      # A page the reply created became home only because the site had none,
      # so deleting it, once nothing else depends on it, puts the site back as
      # it was; DestroyPage's rule that a site keeps its home is for the
      # editor. A revision never changed the home flag, and a home page's
      # blank slug is not restored because SavePage would read it as
      # "generate one".
      def revert!(entry, page)
        return page.destroy! if entry["created"]

        params = entry.slice(*RESTORED)
        params.delete("slug") if page.home?
        result = Websites::Activities::SavePage.call(page: page, params: params, structure_editable: true)
        return if result.success?

        details = Array(result.errors).join(I18n.t("ai_assistant.assistant.website.detail_separator"))
        raise Refused, [t("errors.restore_failed", title: page.title, details: details)]
      end

      def mark_undone!
        metadata = @message.metadata_json.deep_dup
        metadata[KEY] = metadata[KEY].merge("undone_at" => Time.current.iso8601)
        @message.update!(metadata: metadata)
      end

      def t(key, **options)
        I18n.t("ai_assistant.assistant.website.undo.#{key}", **options)
      end
    end
  end
end
