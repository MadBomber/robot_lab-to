# frozen_string_literal: true

module RobotLab
  module To
    # Exponential backoff with interruptible sleep.
    #
    # Formula: 60 * 2^(consecutive_errors - 1) seconds
    #   1 error →  60s
    #   2 errors → 120s
    #   3 errors → 240s
    class Backoff
      BASE_SECONDS = 60

      def initialize
        @interrupted = false
      end

      def sleep_for(consecutive_errors)
        @interrupted = false
        return if consecutive_errors <= 0

        duration = (BASE_SECONDS * (2**(consecutive_errors - 1))).to_i
        duration.times do
          return if @interrupted

          sleep(1)
        end
      end

      # Sleep a fixed number of seconds, interruptibly (1s ticks). Used for
      # polling a blocking decision file. Does NOT reset @interrupted: once a
      # signal fires, subsequent waits return immediately so shutdown is prompt.
      def sleep_seconds(seconds)
        seconds.to_i.times do
          return if @interrupted

          sleep(1)
        end
      end

      def interrupt!
        @interrupted = true
      end
    end
  end
end
