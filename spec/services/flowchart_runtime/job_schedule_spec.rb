# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::JobSchedule do
  let(:job_instance) { instance_double(ActiveJob::Base, job_id: "abc", successfully_enqueued?: true) }
  let(:configured)   { double("configured", perform_later: job_instance) } # rubocop:disable RSpec/VerifiedDoubles
  let(:job_class)    { double("JobClass", set: configured, perform_later: job_instance) } # rubocop:disable RSpec/VerifiedDoubles

  describe ".enqueue!" do
    it "passes validated scheduling options to Active Job" do
      expect(job_class).to receive(:set).with(queue: "mailers", priority: 10).and_return(configured)
      described_class.enqueue!(job_class, args: [1], queue: "mailers", priority: 10)
    end

    it "forwards the arguments to perform_later" do
      expect(configured).to receive(:perform_later).with(1, 2).and_return(job_instance)
      described_class.enqueue!(job_class, args: [1, 2], queue: "default")
    end

    it "calls perform_later directly when no options are given" do
      expect(job_class).to receive(:perform_later).with(no_args).and_return(job_instance)
      described_class.enqueue!(job_class)
    end

    it "raises when Active Job refuses the enqueue" do
      allow(configured).to receive(:perform_later).and_return(false)
      expect { described_class.enqueue!(job_class, queue: "default") }
        .to raise_error(described_class::Error, /not enqueued/)
    end

    it "raises when a callback aborted the enqueue" do
      aborted = instance_double(ActiveJob::Base, successfully_enqueued?: false)
      allow(configured).to receive(:perform_later).and_return(aborted)
      expect { described_class.enqueue!(job_class, queue: "default") }
        .to raise_error(described_class::Error, /not enqueued/)
    end

    it "rejects an object that is not an Active Job class" do
      expect { described_class.enqueue!(Object.new) }
        .to raise_error(described_class::Error, /Active Job/)
    end

    it "rejects an unsafe queue name" do
      expect { described_class.enqueue!(job_class, queue: "bad queue; drop") }
        .to raise_error(described_class::Error, /queue/)
    end

    it "rejects an out-of-range priority" do
      expect { described_class.enqueue!(job_class, priority: described_class::MAX_PRIORITY + 1) }
        .to raise_error(described_class::Error, /priority/)
      expect { described_class.enqueue!(job_class, priority: -1) }
        .to raise_error(described_class::Error, /priority/)
      expect { described_class.enqueue!(job_class, priority: "soon") }
        .to raise_error(described_class::Error, /priority/)
    end
  end

  describe ".bounded_wait" do
    it "keeps a delay inside the maximum" do
      expect(described_class.bounded_wait(60)).to eq(60.seconds)
    end

    it "clamps a delay beyond the maximum" do
      expect(described_class.bounded_wait(described_class::MAX_WAIT_SECONDS * 10))
        .to eq(described_class::MAX_WAIT_SECONDS.seconds)
    end

    it "rejects a negative delay" do
      expect { described_class.bounded_wait(-1) }.to raise_error(described_class::Error, /wait/)
    end

    it "rejects a non-numeric delay" do
      expect { described_class.bounded_wait("soon") }.to raise_error(described_class::Error, /wait/)
    end
  end

  describe ".bounded_wait_until" do
    it "keeps a time inside the horizon" do
      target = 1.hour.from_now
      expect(described_class.bounded_wait_until(target)).to be_within(1.second).of(target)
    end

    it "clamps a time beyond the horizon" do
      result = described_class.bounded_wait_until(10.years.from_now)
      expect(result).to be_within(1.minute).of(Time.current + described_class::MAX_WAIT_SECONDS.seconds)
    end

    it "brings a past time forward to now" do
      expect(described_class.bounded_wait_until(1.hour.ago)).to be_within(1.minute).of(Time.current)
    end

    it "parses a string time" do
      expect(described_class.bounded_wait_until(1.hour.from_now.iso8601))
        .to be_within(1.minute).of(1.hour.from_now)
    end

    it "rejects an unparseable time" do
      expect { described_class.bounded_wait_until("whenever") }
        .to raise_error(described_class::Error, /time/)
    end
  end

  describe ".run" do
    it "enqueues immediately for schedule_when now" do
      expect(job_class).to receive(:set).with(queue: "default").and_return(configured)
      expect(described_class.run(job_class, schedule_when: "now", queue: "default")).to eq("abc")
    end

    it "enqueues after a delay for schedule_when after" do
      expect(job_class).to receive(:set).with(wait: 60.seconds).and_return(configured)
      described_class.run(job_class, schedule_when: "after", wait_seconds: 60)
    end

    it "pre-books interval recurrences starting after one interval, not immediately" do
      expect(job_class).to receive(:set).with(wait: 60.seconds).and_return(configured)
      expect(job_class).to receive(:set).with(wait: 120.seconds).and_return(configured)
      ids = described_class.run(
        job_class,
        schedule_when: "recurring",
        interval_seconds: 60,
        recurrence_limit: 2
      )
      expect(ids).to eq(%w[abc abc])
    end
  end

  describe ".job_id" do
    it "returns the Active Job id when the adapter returned a job instance" do
      job = double("Job", job_id: "abc-123")
      expect(described_class.job_id(job)).to eq("abc-123")
    end

    it "returns nil when the adapter returned a bare truthy value" do
      expect(described_class.job_id(true)).to be_nil
    end

    it "returns nil for nil" do
      expect(described_class.job_id(nil)).to be_nil
    end
  end
end
