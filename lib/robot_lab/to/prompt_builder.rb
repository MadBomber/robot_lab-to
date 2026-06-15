# frozen_string_literal: true

module RobotLab
  module To
    # Builds the per-iteration system prompt injected into each robot.
    class PromptBuilder
      def initialize(config)
        @config = config
      end

      def build(run, notes_content, pending_commit_failure: nil)
        sections = [role_section(run), notes_section(run, notes_content),
                    task_section, submit_section]
        sections << repair_section(pending_commit_failure) if pending_commit_failure
        sections << stop_when_section(@config.stop_when) if @config.stop_when
        sections.join("\n\n")
      end

      private

      def role_section(run)
        <<~MD.chomp
          You are an autonomous software engineer working on the following objective:

          **#{run.objective}**

          You are on iteration #{run.iteration}. Work incrementally — make ONE focused improvement per iteration.
        MD
      end

      def notes_section(run, content)
        <<~MD.chomp
          ## Prior Work (notes.md)

          Read the notes below to understand what has been done in previous iterations.
          Do NOT modify notes.md — it is maintained automatically by the orchestrator.

          File path: #{run.notes_path}

          ```
          #{content.strip.empty? ? "(no iterations yet)" : content.strip}
          ```
        MD
      end

      def task_section
        <<~MD.chomp
          ## Your Task

          1. Make ONE focused, meaningful change toward the objective.
          2. Before finishing: stop any background processes (dev servers, watchers, browsers).
          3. Before finishing: run tests, build, or linters if they exist in the project.
          4. A complete no-op (no file changes AND no new learnings) is NOT success — set success=false.
        MD
      end

      def submit_section
        <<~MD.chomp
          ## Required: Submit Your Result

          You MUST call `submit_iteration_result` as your FINAL action. Include:
          - success: true/false
          - summary: one sentence describing what you did or why you stopped
          - key_changes: list of files or changes made
          - key_learnings: insights worth recording for future iterations
        MD
      end

      def repair_section(error)
        <<~MD.chomp
          ## ⚠ Previous Commit Failure — Repair Required

          The previous iteration completed successfully but git commit failed with:

          ```
          #{error.output}
          ```

          **Fix the uncommitted changes first** before doing anything else. Once the
          commit issue is resolved, call submit_iteration_result with success=true.
        MD
      end

      def stop_when_section(condition)
        <<~MD.chomp
          ## Stop Condition

          After completing your work, evaluate whether the following condition is met:

          > #{condition}

          If the condition is met AND this iteration was successful, set should_fully_stop=true
          in your submit_iteration_result call.
        MD
      end
    end
  end
end
