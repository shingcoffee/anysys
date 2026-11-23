# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Conversation do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, customer: customer) }

  it "is TenantScoped and stamps activity on create" do
    conversation = described_class.start_for(customer: customer, user: user)

    expect(conversation.customer_id).to eq(customer.id)
    expect(conversation.last_active_at).to be_within(5.seconds).of(Time.current)
  end

  it "keeps more than one thread per (customer, user) pair" do
    first = described_class.start_for(customer: customer, user: user)
    second = described_class.start_for(customer: customer, user: user)

    expect(second).not_to eq(first)
    expect(described_class.owned_by(customer: customer, user: user).count).to eq(2)
  end

  describe ".current_for" do
    it "opens a thread for a user who has never chatted" do
      expect { described_class.current_for(customer: customer, user: user) }
        .to change(described_class, :count).by(1)
    end

    it "returns the most recently active unarchived thread" do
      create(:ai_assistant_conversation, customer: customer, user: user, last_active_at: 2.days.ago)
      newest = create(:ai_assistant_conversation, customer: customer, user: user, last_active_at: 1.hour.ago)

      expect(described_class.current_for(customer: customer, user: user)).to eq(newest)
    end

    it "skips archived threads rather than reopening one" do
      create(:ai_assistant_conversation, :archived, customer: customer, user: user)

      current = described_class.current_for(customer: customer, user: user)

      expect(current).not_to be_archived
      expect(current).to be_persisted
    end

    it "returns an existing active thread without writing" do
      existing = create(:ai_assistant_conversation, customer: customer, user: user)

      expect { described_class.current_for(customer: customer, user: user) }
        .not_to change { existing.reload.updated_at }
      expect(described_class.current_for(customer: customer, user: user)).to eq(existing)
      expect(existing.reload).not_to be_archived
    end

    # Regression: this runs from a GET, and it used to call start_for
    # unconditionally. A user at the ceiling who archived their last active
    # thread and reloaded the page got thread 51, 52, 53… without bound.
    describe "at the per-user ceiling" do
      def fill_to_capacity(active: 0)
        archived = described_class::MAX_PER_USER - active - 1
        archived.times do
          create(:ai_assistant_conversation, :archived, customer: customer, user: user,
                 last_active_at: 10.days.ago)
        end
        active.times do |index|
          create(:ai_assistant_conversation, customer: customer, user: user,
                 last_active_at: (index + 2).hours.ago)
        end
        create(:ai_assistant_conversation, :archived, customer: customer, user: user,
               last_active_at: 1.hour.ago)
      end

      it "reopens the most recently active archived thread instead of creating one" do
        newest_filed = fill_to_capacity
        reopened = nil

        expect { reopened = described_class.current_for(customer: customer, user: user) }
          .not_to change(described_class, :count)
        expect(reopened).to eq(newest_filed)
      end

      it "returns the reopened thread unarchived, so the page can show its transcript" do
        newest_filed = fill_to_capacity

        reopened = described_class.current_for(customer: customer, user: user)

        expect(reopened).not_to be_archived
        expect(newest_filed.reload).not_to be_archived
      end

      it "does not walk the count past the ceiling on repeated page loads" do
        fill_to_capacity

        3.times { described_class.current_for(customer: customer, user: user) }

        expect(described_class.owned_by(customer: customer, user: user).count)
          .to eq(described_class::MAX_PER_USER)
      end

      it "prefers an active thread over reopening an archived one" do
        fill_to_capacity(active: 1)
        active = described_class.owned_by(customer: customer, user: user).active.sole

        expect { expect(described_class.current_for(customer: customer, user: user)).to eq(active) }
          .not_to change(described_class, :count)
      end

      it "does not count another user's threads towards the ceiling" do
        fill_to_capacity
        other = create(:user, customer: customer)

        expect { described_class.current_for(customer: customer, user: other) }
          .to change(described_class, :count).by(1)
      end
    end
  end

  describe ".resolve" do
    it "reads a blank id as the current thread" do
      newest = create(:ai_assistant_conversation, customer: customer, user: user)

      expect(described_class.resolve(customer: customer, user: user, id: nil)).to eq(newest)
      expect(described_class.resolve(customer: customer, user: user, id: "")).to eq(newest)
    end

    it "returns the named thread when the caller owns it" do
      mine = create(:ai_assistant_conversation, customer: customer, user: user)

      expect(described_class.resolve(customer: customer, user: user, id: mine.id)).to eq(mine)
    end

    it "refuses another user's thread in the same tenant" do
      other = create(:user, customer: customer)
      foreign = create(:ai_assistant_conversation, customer: customer, user: other)

      expect(described_class.resolve(customer: customer, user: user, id: foreign.id)).to be_nil
    end

    it "refuses the same user's thread in another tenant" do
      other_tenant = create(:customer)
      foreign = create(:ai_assistant_conversation, customer: other_tenant, user: user)

      expect(described_class.resolve(customer: customer, user: user, id: foreign.id)).to be_nil
    end

    it "returns nil for an id that does not exist" do
      expect(described_class.resolve(customer: customer, user: user, id: 999_999)).to be_nil
    end
  end

  describe ".at_capacity?" do
    it "is false below the per-user ceiling" do
      expect(described_class.at_capacity?(customer: customer, user: user)).to be false
    end

    it "is true at the per-user ceiling, counting archived threads" do
      described_class::MAX_PER_USER.times do
        create(:ai_assistant_conversation, :archived, customer: customer, user: user)
      end

      expect(described_class.at_capacity?(customer: customer, user: user)).to be true
    end

    it "does not count another user's threads" do
      other = create(:user, customer: customer)
      described_class::MAX_PER_USER.times do
        create(:ai_assistant_conversation, customer: customer, user: other)
      end

      expect(described_class.at_capacity?(customer: customer, user: user)).to be false
    end
  end

  it "enforces the quota for direct and lazy starts through the same serialized writer" do
    described_class::MAX_PER_USER.times do
      create(:ai_assistant_conversation, :archived, customer: customer, user: user)
    end
    expect { expect(described_class.start_for(customer: customer, user: user)).to be_nil }
      .not_to change(described_class, :count)
    expect { described_class.current_for(customer: customer, user: user) }
      .not_to change(described_class, :count)
    expect(described_class.owned_by(customer: customer, user: user).active.count).to eq(1)
  end

  # The sidebar is re-rendered on every message send, not just on page load,
  # so the per-row borrowed-title lookup was paid far more often than it read.
  describe ".preload_fallback_titles" do
    def untitled_thread(prompt: nil, **attrs)
      create(:ai_assistant_conversation, customer: customer, user: user, **attrs).tap do |row|
        create(:ai_assistant_message, customer: customer, conversation: row, body: prompt) if prompt
      end
    end

    it "borrows each untitled thread's opening prompt" do
      rows = [ untitled_thread(prompt: "Import the cohort list"), untitled_thread(prompt: "Add a Notes field") ]

      described_class.preload_fallback_titles(rows)

      expect(rows.map(&:display_title)).to eq([ "Import the cohort list", "Add a Notes field" ])
    end

    it "borrows the first user prompt, not the latest one" do
      row = untitled_thread(prompt: "First question")
      create(:ai_assistant_message, customer: customer, conversation: row, body: "Second question")

      described_class.preload_fallback_titles([ row ])

      expect(row.display_title).to eq("First question")
    end

    it "ignores assistant turns when borrowing" do
      row = untitled_thread
      create(:ai_assistant_message, :assistant, customer: customer, conversation: row, body: "Hi there.")
      create(:ai_assistant_message, customer: customer, conversation: row, body: "My question")

      described_class.preload_fallback_titles([ row ])

      expect(row.display_title).to eq("My question")
    end

    it "truncates a borrowed title to the sidebar limit" do
      row = untitled_thread(prompt: "word " * 40)

      described_class.preload_fallback_titles([ row ])

      expect(row.display_title.length).to eq(described_class::TITLE_LIMIT)
      expect(row.display_title).to end_with("…")
    end

    it "leaves a named thread alone and looks up no messages for it" do
      rows = [ create(:ai_assistant_conversation, :titled, customer: customer, user: user) ]
      named = rows.first.title

      expect(AiAssistant::Message).not_to receive(:where)
      expect(described_class.preload_fallback_titles(rows)).to eq(rows)
      expect(rows.first.display_title).to eq(named)
    end

    it "falls back to the untitled copy for a thread with no turns" do
      row = untitled_thread

      described_class.preload_fallback_titles([ row ])

      expect(row.display_title).to eq(I18n.t("ai_assistant.assistant.conversations.untitled"))
    end

    it "resolves the whole list in two queries rather than one per row" do
      rows = Array.new(5) { |index| untitled_thread(prompt: "Question #{index}") }

      expect(count_queries { described_class.preload_fallback_titles(rows) }).to eq(2)
    end

    it "leaves display_title with nothing left to look up" do
      rows = Array.new(3) { |index| untitled_thread(prompt: "Question #{index}") }
      described_class.preload_fallback_titles(rows)

      expect(count_queries { rows.map(&:display_title) }).to eq(0)
    end

    it "mixes titled and untitled rows in the same pass" do
      titled = create(:ai_assistant_conversation, :titled, customer: customer, user: user)
      borrowed = untitled_thread(prompt: "Borrowed name")

      described_class.preload_fallback_titles([ titled, borrowed ])

      expect(titled.display_title).to eq(titled.title)
      expect(borrowed.display_title).to eq("Borrowed name")
    end
  end

  describe "#display_title" do
    it "resolves a row that was never preloaded" do
      row = create(:ai_assistant_conversation, customer: customer, user: user)
      create(:ai_assistant_message, customer: customer, conversation: row, body: "Lazy lookup")

      expect(row.display_title).to eq("Lazy lookup")
    end

    it "prefers a real title over a borrowed one" do
      row = create(:ai_assistant_conversation, :titled, customer: customer, user: user)
      create(:ai_assistant_message, customer: customer, conversation: row, body: "Not this")

      expect(row.display_title).to eq(row.title)
    end

    it "falls back to the untitled copy for an empty thread that was never preloaded" do
      row = create(:ai_assistant_conversation, customer: customer, user: user)

      expect(row.display_title).to eq(I18n.t("ai_assistant.assistant.conversations.untitled"))
    end
  end
end

RSpec.describe AiAssistant::Message do
  it "accepts user and assistant roles" do
    message = create(:ai_assistant_message, role: "user")
    expect(message).to be_user
    assistant = create(:ai_assistant_message, :assistant, conversation: message.conversation, customer: message.customer)
    expect(assistant).to be_assistant
  end
end
