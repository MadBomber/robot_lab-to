# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class BackoffTest < Minitest::Test
      def test_interrupt_cancels_sleep_immediately
        backoff = Backoff.new
        start = Time.now
        thread = Thread.new { backoff.sleep_for(1) }
        sleep(0.05)
        backoff.interrupt!
        thread.join(2)
        assert(Time.now - start < 5, "interrupt should stop sleep well before 60s")
      end

      def test_sleep_for_zero_errors_is_zero
        backoff = Backoff.new
        backoff.interrupt!
        start = Time.now
        backoff.sleep_for(0)
        assert(Time.now - start < 1)
      end

      def test_sleep_seconds_returns_immediately_when_interrupted
        backoff = Backoff.new
        backoff.interrupt!
        start = Time.now
        backoff.sleep_seconds(30)
        assert(Time.now - start < 1, "an interrupted poll-sleep must not block")
      end

      def test_sleep_seconds_zero_is_immediate
        backoff = Backoff.new
        start = Time.now
        backoff.sleep_seconds(0)
        assert(Time.now - start < 1)
      end

      def test_sleep_seconds_interruptible_mid_wait
        backoff = Backoff.new
        start = Time.now
        thread = Thread.new { backoff.sleep_seconds(30) }
        sleep(0.05)
        backoff.interrupt!
        thread.join(3)
        assert(Time.now - start < 3, "interrupt should end the poll-sleep promptly")
      end
    end
  end
end
