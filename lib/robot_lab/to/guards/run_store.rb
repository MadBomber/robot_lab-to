# frozen_string_literal: true

module RobotLab
  module To
    module Guards
      # Per-run shared state for the guards.
      #
      # RobotLab creates a fresh tool-call HookContext per call with its own
      # ExtensionState, so cross-call guard state (the read-set, checkpoint-set,
      # loop tracker) cannot live in ctx.local. robot_lab-to runs each iteration
      # in its own thread (Orchestrator#run_robot_with_interrupt), so a
      # thread-local is a clean per-run scope — the same idiom robot_lab-audit
      # uses for run ids. before_run resets it; the thread ends with the
      # iteration, so nothing leaks across runs.
      module RunStore
        module_function

        # Set/replace the value for `key`.
        def reset(key, value)
          Thread.current[key] = value
        end

        # Fetch the value for `key`, initializing to `default` when unset.
        def fetch(key, default = nil)
          value = Thread.current[key]
          return value unless value.nil?

          Thread.current[key] = default
        end
      end
    end
  end
end
