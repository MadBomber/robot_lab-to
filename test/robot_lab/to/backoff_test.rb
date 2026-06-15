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
    end
  end
end
