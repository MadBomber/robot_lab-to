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
