# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class JsonlLoggerTest < Minitest::Test
      def test_log_before_open_buffers_events
        logger = JsonlLogger.new
        logger.log("test:event", key: "value")
        assert_equal 1, logger.instance_variable_get(:@buffer).size
      end

      def test_open_flushes_buffer_to_file
        with_tmp_dir do |dir|
          path = dir.join("run.log")
          logger = JsonlLogger.new
          logger.log("pre:open", msg: "hello")
          logger.open(path)
          logger.close
          lines = path.readlines
          assert_equal 1, lines.size
          assert_includes lines.first, "pre:open"
        end
      end

      def test_log_after_open_writes_directly
        with_tmp_dir do |dir|
          path = dir.join("run.log")
          logger = JsonlLogger.new
          logger.open(path)
          logger.log("post:open", iteration: 1)
          logger.close
          content = path.read
          assert_includes content, "post:open"
          assert_includes content, '"iteration":1'
        end
      end

      def test_log_entry_is_valid_json
        with_tmp_dir do |dir|
          path = dir.join("run.log")
          logger = JsonlLogger.new
          logger.open(path)
          logger.log("some:event", x: 42)
          logger.close
          parsed = JSON.parse(path.readlines.first)
          assert_equal "some:event", parsed["event"]
          assert_equal 42, parsed["x"]
          assert parsed.key?("ts")
        end
      end

      def test_close_makes_file_unwritable
        with_tmp_dir do |dir|
          path = dir.join("run.log")
          logger = JsonlLogger.new
          logger.open(path)
          logger.close
          assert_nil logger.instance_variable_get(:@file)
        end
      end

      def test_buffer_cap_drops_oldest_events
        logger = JsonlLogger.new
        (JsonlLogger::MAX_BUFFER + 5).times { |i| logger.log("event:#{i}") }
        assert_equal JsonlLogger::MAX_BUFFER, logger.instance_variable_get(:@buffer).size
      end

      def test_buffer_cleared_after_open
        with_tmp_dir do |dir|
          path = dir.join("run.log")
          logger = JsonlLogger.new
          3.times { |i| logger.log("buffered:#{i}") }
          logger.open(path)
          assert_empty logger.instance_variable_get(:@buffer)
          logger.close
        end
      end

      def test_multiple_log_calls_written_in_order
        with_tmp_dir do |dir|
          path = dir.join("run.log")
          logger = JsonlLogger.new
          logger.open(path)
          %w[first second third].each { |e| logger.log(e) }
          logger.close
          events = path.readlines.map { |l| JSON.parse(l)["event"] }
          assert_equal %w[first second third], events
        end
      end
    end
  end
end
