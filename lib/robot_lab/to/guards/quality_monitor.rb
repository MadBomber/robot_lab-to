# frozen_string_literal: true

require "json"
require_relative "run_store"

module RobotLab
  module To
    module Guards
      # Response-quality monitor, ported from little-coder quality-monitor.
      # Detects the degenerate output modes that waste a small local model's
      # token budget on an unattended overnight run:
      #
      #   repeated_tool_call  — exact name+args match with the previous call
      #   empty_response      — final turn produced no text and no tool calls
      #
      # Loop detection (repeated_tool_call) is the highest-value guard: it is
      # what stops a 9-35B model spinning on the same call until max_tokens. It
      # runs in after_tool_call (RobotLab fires the llm_generation hook only once
      # per run, so per-round comparison must key off tool calls), with the
      # previous call held in the per-run RunStore.
      #
      # RobotLab gives no in-flight "steer" primitive, so after MAX_CONSECUTIVE
      # repeats we raise QualityError. Orchestrator#execute_iteration already
      # rescues iteration errors — it rolls back and records the reason in
      # notes.md, so the next iteration's prompt carries the correction forward.
      class QualityMonitor < RobotLab::Hook
        self.namespace = :quality_monitor

        KEY = :robot_lab_to_quality
        MAX_CONSECUTIVE = 2

        # Raised when the model exceeds the consecutive-repeat budget.
        class QualityError < StandardError
          attr_reader :reason

          def initialize(reason)
            @reason = reason
            super("response quality failure: #{reason}")
          end
        end

        class << self
          def before_run(_ctx)
            RunStore.reset(KEY, { previous: nil, repeats: 0 })
          end

          # Per-call loop detection. This is the load-bearing guard: it stops a
          # small model spinning on the same tool call until the token budget is
          # gone. Empty-response / no-progress handling is intentionally left to
          # the orchestrator's submit-nudge → not_submitted path, which recovers
          # gracefully instead of hard-erroring the iteration.
          def after_tool_call(ctx)
            call = { name: ctx.tool_name.to_s, input: ctx.tool_args }
            state = RunStore.fetch(KEY, { previous: nil, repeats: 0 })

            if repeated?([call], [state[:previous]].compact)
              state[:repeats] += 1
              raise QualityError, :repeated_tool_call if state[:repeats] > MAX_CONSECUTIVE
            else
              state[:repeats] = 0
            end
            state[:previous] = call
          end

          # ---- pure logic (testable in isolation) -----------------------------

          # @param text [String]
          # @param calls [Array<Hash>] each {name:, input:}
          # @param previous [Array<Hash>] previous round's calls
          # @param known [Array<String>] registered tool names (optional)
          # @return [Symbol, String] :ok or a failure reason
          def assess(text, calls, previous, known)
            return :empty_response if text.to_s.strip.empty? && calls.empty?

            calls.each do |c|
              return :empty_tool_name if c[:name].to_s.empty?
              return "unknown_tool:#{c[:name]}" if known.any? && !known.include?(c[:name])
            end

            return :repeated_tool_call if repeated?(calls, previous)

            :ok
          end

          # True when any current call exactly matches any previous call.
          def repeated?(calls, previous)
            return false if calls.empty? || previous.empty?

            calls.any? do |c|
              previous.any? do |p|
                c[:name] == p[:name] && JSON.generate(c[:input]) == JSON.generate(p[:input])
              end
            end
          end

          def correction_message(reason)
            case reason.to_s
            when "repeated_tool_call"
              "You repeated the previous tool call verbatim — you appear to be " \
              "stuck. Try a different approach or explain what is blocking you."
            when "empty_response"
              "Your response was empty. Respond with text or a tool call to make progress."
            when /\Aunknown_tool:/
              "Tool '#{reason.to_s.split(':', 2).last}' does not exist. Use only your registered tools."
            else
              "Response quality issue (#{reason}). Please correct and continue."
            end
          end
        end
      end
    end
  end
end
