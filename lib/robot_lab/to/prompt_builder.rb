# frozen_string_literal: true

module RobotLab
  module To
    # Builds the per-iteration system prompt injected into each robot.
    class PromptBuilder
      def initialize(config)
        @config = config
      end

      def build(run, notes_content, workspace: nil, pending_commit_failure: nil, resolved_decisions: [])
        sections = [role_section(run), notes_section(run, notes_content)]
        sections << workspace_section(workspace) if workspace && !workspace.empty?
        sections << decisions_answered_section(resolved_decisions) if resolved_decisions && !resolved_decisions.empty?
        sections << task_section
        sections << verify_section if @config.verify_command
        sections << decision_guidance_section if @config.decisions_enabled?
        sections << submit_section
        sections << repair_section(pending_commit_failure) if pending_commit_failure
        sections << stop_when_section(@config.stop_when) if @config.stop_when
        sections.join("\n\n")
      end

      private

      # Feed back the human's answers to questions the robot raised earlier so it
      # acts on them this iteration instead of re-raising the same decision.
      def decisions_answered_section(decisions)
        items = decisions.map do |d|
          "- **#{d.question}**\n  → Human decision: #{d.resolution || "(resolved — see #{d.path})"}"
        end.join("\n")

        <<~MD.chomp
          ## Answered Decisions

          A human has answered questions you raised in earlier iterations. Act on
          these decisions now — do NOT raise them again:

          #{items}
        MD
      end

      # Calibration guidance: the article's hardest problem is teaching the agent
      # WHEN to escalate. Name the bar explicitly.
      def decision_guidance_section
        <<~MD.chomp
          ## When to Ask for a Human Decision

          You have a `request_decision` tool. Use it ONLY for a choice that is
          irreversible or hard to reverse, that sets a public contract, that is
          genuinely ambiguous about the intent behind the objective, or that
          falls outside the objective's scope. Always include your recommended
          option and reasoning (your "lean"). Set blocking=true only when work
          cannot correctly continue without the answer.

          Do NOT use it for routine engineering choices you are equipped to make
          yourself — naming, structure, library selection within scope, and the
          like. Prefer making progress over asking.
        MD
      end

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
