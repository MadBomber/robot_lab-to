# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class GuardsTest < Minitest::Test
      # Records on() registrations without needing a live LLM robot.
      class RecordingRobot
        attr_reader :registrations

        def initialize
          @registrations = []
        end

        def on(handler, context: nil)
          @registrations << [handler, context]
        end
      end

      def test_install_registers_every_guard
        robot = RecordingRobot.new
        Guards.install(robot)
        handlers = robot.registrations.map(&:first)
        Guards::ALL.each { |g| assert_includes handlers, g }
      end

      def test_install_omits_guards_in_except_list
        robot = RecordingRobot.new
        Guards.install(robot, except: [Guards::WriteGuard])
        handlers = robot.registrations.map(&:first)
        refute_includes handlers, Guards::WriteGuard, "excepted guard must be skipped"
        assert_includes handlers, Guards::Checkpoint, "other guards still install"
        assert_includes handlers, Guards::ReadBeforeEdit
      end

      def test_install_includes_write_guard_by_default
        robot = RecordingRobot.new
        Guards.install(robot)
        assert_includes robot.registrations.map(&:first), Guards::WriteGuard
      end

      def test_config_write_guard_defaults_true
        assert Config.new.write_guard
      end

      def test_config_write_guard_override
        refute Config.new(write_guard: false).write_guard
      end

      def test_install_passes_run_context_to_checkpoint
        robot = RecordingRobot.new
        stub_run do |run, _dir|
          Guards.install(robot, run: run)
          checkpoint = robot.registrations.find { |h, _| h == Guards::Checkpoint }
          assert_equal run, checkpoint.last[:run]
        end
      end

      def test_config_local_guards_defaults_false
        refute Config.new.local_guards?
      end

      def test_config_local_guards_override
        assert Config.new(local_guards: true).local_guards?
      end
    end
  end
end
