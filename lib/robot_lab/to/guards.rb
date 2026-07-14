# frozen_string_literal: true

require_relative "guards/run_store"
require_relative "guards/path_resolution"
require_relative "guards/write_guard"
require_relative "guards/read_before_edit"
require_relative "guards/checkpoint"
require_relative "guards/quality_monitor"
require_relative "guards/grader_lock"

module RobotLab
  module To
    # Small-model guardrails ported from little-coder (Apache-2.0).
    #
    # These RobotLab::Hook subclasses make file/bash tools safe for a small
    # *local* model driving an autonomous robot_lab-to loop. They are no-ops
    # for a frontier model, so registration is opt-in.
    #
    # Wire them onto a per-iteration robot in Orchestrator#build_robot:
    #
    #   robot = RobotLab.build(...)
    #   RobotLab::To::Guards.install(robot, run: @run) if @config.local_guards
    #   robot
    #
    # Each guard is single-purpose and independently testable: its class methods
    # take a HookContext and have no hidden global state beyond a per-robot store
    # that is reset on before_run.
    module Guards
      ALL = [
        Guards::WriteGuard,
        Guards::ReadBeforeEdit,
        Guards::Checkpoint,
        Guards::QualityMonitor
      ].freeze

      # Register every guard on a robot.
      #
      # @param robot [RobotLab::Robot]
      # @param run [RobotLab::To::Run, nil] supplies run_dir for checkpoints
      # @return [RobotLab::Robot] the same robot, for chaining
      # `except:` lists guard classes to skip. Passing [WriteGuard] lets a robot
      # overwrite existing files (WriteGuard otherwise refuses Write on an existing
      # file and redirects to Edit -- unhelpful for iterative prose that rewrites a
      # draft).
      def self.install(robot, run: nil, except: [])
        active = ALL - Array(except)
        robot.on(Guards::Checkpoint, context: { run: run }) if run
        (active - [Guards::Checkpoint]).each { |guard| robot.on(guard) }
        robot.on(Guards::Checkpoint) unless run
        robot
      end
    end
  end
end
