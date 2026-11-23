# frozen_string_literal: true

require "rails_helper"
require "concurrent"

RSpec.describe "Concurrent shortcut and website path reservations" do
  self.use_transactional_tests = false

  before do
    raise "Concurrent writers require committed fixtures" if ActiveRecord::Base.connection.transaction_open?

    @customer = create(:customer)
    existing_module = FeatureModules::Module.find_by(key: "website")
    @module_attributes = existing_module&.attributes&.slice("name", "status")
    @website_module = enable_module!("website", @customer, name: "Website")
    @website = create(:website, :published, customer: @customer)
    @destination = create(:page, :for_member, :for_public, customer: @customer, launched: true)
    # Load both workflows before starting threads (Zeitwerk's first-load lock
    # must not become part of the database coordination).
    PageShortcuts::Activities::Save
    Websites::Activities::SavePage
  end

  after do
    Current.reset
    PageShortcut.where(customer_id: @customer.id).delete_all
    @website&.destroy!
    @destination&.destroy!
    @customer.destroy!
    if @module_attributes
      @website_module.update!(@module_attributes)
    else
      @website_module&.destroy!
    end
  end

  def write(kind)
    if kind == :shortcut
      PageShortcuts::Activities::Save.call(
        shortcut: PageShortcut.new, customer_id: @customer.id,
        params: { path: "/contested", target: "Page:#{@destination.id}" }
      )
    else
      Websites::Activities::SavePage.call(
        page: build(:website_page, website: @website, customer: @customer),
        structure_editable: true,
        params: { title: "Contested website page", slug: "contested", published: true }
      )
    end
  end

  def competing_writes(first:)
    second = first == :shortcut ? :website : :shortcut
    ready = Concurrent::CyclicBarrier.new(3)
    checked = Concurrent::Event.new
    contender_started = Concurrent::Event.new
    collision_table = first == :shortcut ? "website_pages" : "page_shortcuts"
    observer = Object.new
    observer.define_singleton_method(:start) do |_name, _id, payload|
      if Thread.current[:shortcut_writer] == second && payload[:sql].match?(/\ABEGIN\b/i)
        contender_started.set
      end
    end
    observer.define_singleton_method(:finish) do |_name, _id, payload|
      next unless Thread.current[:shortcut_writer] == first && !checked.set?
      next unless payload[:sql].match?(/\bFROM\s+"?#{collision_table}"?\b/i)

      # Pause after the winner's real collision read, before its persistence.
      # The other connection then attempts its transaction. SQLite's IMMEDIATE
      # transaction (or a customer row lock) keeps its validation behind ours.
      checked.set
      raise "competing writer did not start" unless contender_started.wait(10)
    end

    workers = {}
    ActiveSupport::Notifications.subscribed(observer, "sql.active_record") do
      [first, second].each do |kind|
        workers[kind] = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            connection.verify!
            raise "writer connections not ready" unless ready.wait(10)
            raise "first writer did not check collisions" if kind == second && !checked.wait(10)

            Thread.current[:shortcut_writer] = kind
            write(kind)
          ensure
            Thread.current[:shortcut_writer] = nil
            Current.reset
          end
        end
        workers[kind].report_on_exception = false
      end
      raise "writer connections not ready" unless ready.wait(10)

      workers.transform_values do |thread|
        raise "writer did not finish" unless thread.join(15)

        thread.value
      end
    end
  ensure
    workers&.each_value do |thread|
      thread.kill if thread.alive?
      thread.join
    end
  end

  %i[shortcut website].each do |first|
    it "keeps the path usable and returns a validation failure when #{first} wins" do
      results = competing_writes(first: first)
      winner = results.fetch(first)
      loser = results.fetch(first == :shortcut ? :website : :shortcut)

      expect(winner.success?).to be(true)
      expect(loser.success?).to be(false)
      expect(loser.model).not_to be_persisted
      if first == :shortcut
        expect(loser.model.errors[:slug]).to include(I18n.t("page_shortcuts.errors.shortcut_slug_taken"))
      else
        expect(loser.errors[:path]).to include(I18n.t("page_shortcuts.errors.website_path_taken"))
      end
      expect(PageShortcut.where(customer_id: @customer.id, path: "/contested").count).to eq(first == :shortcut ? 1 : 0)
      expect(@website.pages.where(slug: "contested").count).to eq(first == :website ? 1 : 0)

      request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/#{@customer.id}/contested"))
      target = PageShortcuts::Resolver.resolve(request)
      destination = first == :shortcut ? @destination : winner.model
      expect(target).to have_attributes(customer_id: @customer.id, target_type: destination.class.name,
                                       target_id: destination.id)
    end
  end
end
