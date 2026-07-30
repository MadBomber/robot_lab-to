# frozen_string_literal: true

require "json"

module RobotLab
  module To
    # Writes structured JSONL events to the run log file.
    #
    # Events emitted before the log file is ready are buffered in memory
    # and flushed on first open (capacity: 100 lines).
    class JsonlLogger
      MAX_BUFFER = 100

      def initialize
        @path   = nil
        @buffer = []
        @file   = nil
      end

      def open(path)
        @path = path
        @file = File.open(path, "a")
        @file.sync = true
        flush_buffer
      end

      def log(event, **payload)
        entry = { event: event, ts: Time.now.iso8601(3) }.merge(payload).compact
        line  = JSON.generate(entry)
        if @file
          @file.write("#{line}\n") # single write keeps the line intact on crash
        else
          @buffer.shift if @buffer.size >= MAX_BUFFER
          @buffer << line
        end
      end

      def close
        if @file
          @file.flush
          begin
            @file.fsync
          rescue SystemCallError
            nil
          end
          @file.close
        end
        @file = nil
      end

      private

      def flush_buffer
        @buffer.each { |line| @file.write("#{line}\n") }
        @buffer.clear
      end
    end
  end
end
