# frozen_string_literal: true

module RobotLab
  module To
    # Builds the per-iteration system prompt injected into each robot.
    class PromptBuilder
      def initialize(config)
        @config = config
      end

      def build(run, notes_content, workspace: nil, pending_commit_failure: nil)
        sections = [role_section(run), notes_section(run, notes_content)]
        sections << workspace_section(workspace) if workspace && !workspace.empty?
        sections << task_section
        sections << verify_section if @config.verify_command
        sections << submit_section
        sections << repair_section(pending_commit_failure) if pending_commit_failure
        sections << stop_when_section(@config.stop_when) if @config.stop_when
        sections.join("\n\n")
      end

      private

      # R3: front-load the project layout so the robot doesn't burn its first
      # several tool calls re-discovering the workspace (ls/find/read) every run.
      def workspace_section(files)
        listing = files.first(200).map { |f| "- #{f}" }.join("\n")
        <<~MD.chomp
          ## Project Files

          The project already contains the files below — read them directly instead
          of re-discovering the layout. (Files you create appear here next iteration.)

          #{listing}
        MD
      end

      # R1: name the exact command the orchestrator will grade this iteration by,
      # so the robot can satisfy it instead of guessing.
      def verify_section
        <<~MD.chomp
          ## Verification — how this iteration is judged

          After your change, the orchestrator runs this EXACT command and only commits
          if it exits 0 — otherwise everything is rolled back:

              #{@config.verify_command}

          Run it yourself and make it pass BEFORE calling submit_iteration_result.
        MD
      end

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
