# frozen_string_literal: true

module RobotLab
  module To
    module Evals
      # Measured / deterministic eval for software products.
      #
      #   verify  - floor gate; a command that must exit 0 (correctness)
      #   measure - optional command printing a number to stdout; higher = better
      #   target  - optional; met_target fires when measured value >= target
      #
      # Composes Verifier for command execution. With no `measure`, it behaves
      # exactly like the original verify-command gate: improved == gate, and
      # met_target never fires (stop falls back to --stop-when).
      class Code < Base
        def initialize(verify: nil, measure: nil, target: nil, timeout: 600, work_dir: Dir.pwd)
          super()
          @verify   = verify
          @measure  = measure
          @target   = target
          @timeout  = timeout
          @work_dir = work_dir
        end

        def score(context)
          gate_ok, output = run_gate
          value           = measure_value
          Score.new(
            gate_ok:    gate_ok,
            improved:   improved?(gate_ok, value, context.previous_value),
            met_target: target_met?(value),
            value:      value,
            detail:     detail_for(gate_ok, value),
            output:     output
          )
        end

        private

        # Returns [passed?, output]. No verify command means the floor is open.
        def run_gate
          return [true, nil] unless @verify

          result = Verifier.new(@verify, work_dir: @work_dir, timeout: @timeout).run
          [result.passed?, result.output]
        end

        # First number the measure command prints, or nil when not measuring.
        def measure_value
          return nil unless @measure

          output = Verifier.new(@measure, work_dir: @work_dir, timeout: @timeout).run.output
          match  = output[/-?\d+(?:\.\d+)?/]
          match&.to_f
        end

        # Without a measured value, any gate-passing change is progress. With one,
        # progress means the value strictly beat the parent (or there is no parent).
        def improved?(gate_ok, value, previous_value)
          return gate_ok if value.nil?

          previous_value.nil? || value > previous_value
        end

        def target_met?(value)
          !@target.nil? && !value.nil? && value >= @target
        end

        def detail_for(gate_ok, value)
          parts = ["verify=#{gate_ok}"]
          parts << "measure=#{value}" unless value.nil?
          parts.join(" ")
        end
      end
    end
  end
end
