# frozen_string_literal: true

require "securerandom"
require "json"

module RobotLab
  module To
    # Main autonomous loop.
    #
    # Creates a new robot per iteration, reads the iteration result from SubmitResultTool,
    # then commits, rolls back, or queues repair depending on the outcome.
    #
    # Human-in-the-loop is asynchronous: when the robot raises a decision it must
    # not make alone, it is written to a decision file (see DecisionManager). A
    # blocking decision either pauses the loop (decision_mode: wait) or stops the
    # run for a later `--resume` (decision_mode: exit).
    #
    # :reek:TooManyMethods :reek:TooManyInstanceVariables -- this is the
    # single object that owns the whole iteration lifecycle (setup, agent
    # turn, eval gate, commit/rollback, decisions, tokens, signals). Splitting
    # it apart would scatter state (@run, @git, @pending_commit_failure,
    # @stop_requested, ...) across collaborators that would just pass it back
    # and forth -- see the "Architecture" section of CLAUDE.md.
    # :reek:RepeatedConditional -- @stop_requested, @pending_commit_failure,
    # and decisions_enabled? are real orchestrator-wide state, legitimately
    # checked at each point that must react to it; that is what a run loop's
    # flags are for, not a sign the checks belong on another object.
    class Orchestrator
      SIGNAL_STOP = "graceful_stop"

      # Sent to a robot that ended its turn without calling submit_result
      # (the "thinks but doesn't act" degenerate case).
      SUBMIT_NUDGE = <<~MSG
        You ended your turn without calling submit_result. You MUST call it now:
        report success: true with a one-sentence summary (and key_changes if you
        modified files), or success: false with what blocked you. Do not do any
        further work first -- just submit the result of what you have done.
      MSG

      def initialize(objective, config, resume_run_id: nil)
        @objective              = objective
        @config                 = config
        @resume_run_id          = resume_run_id
        @stop_requested         = false
        @abort_reason           = nil
        @pending_commit_failure = nil
        @logger                 = JsonlLogger.new  # buffers pre-open events
        @run                    = nil
        @git                    = nil
        @runner_thread          = nil
        @evaluator              = nil
        @robot                  = nil
        @submit_tool            = nil
        @decisions              = nil
        @decision_tool          = nil
        @injected_decisions     = []
        @backoff                = nil
        @builder                = nil
        @notes                  = nil
        @stop_conditions        = nil
        @accounted_in           = 0
        @accounted_out          = 0
      end

      # :reek:TooManyStatements -- top-level run/rescue/ensure sequence for the
      # whole process; the rescue branches are already split into their own
      # error-shaped clauses.
      def run
        @resume_run_id ? setup_resume : setup_run
        install_signal_handlers
        unless @resume_run_id
          @logger.log("orchestrator:start", run_id: @run.run_id, objective: @objective,
                                            branch: @run.branch, model: @config.model)
          progress "run #{@run.run_id} → branch #{@run.branch}"
        end
        main_loop
      rescue AbortError => e
        @abort_reason = e.reason
        @logger.log("orchestrator:abort", reason: @abort_reason)
      rescue PermanentError => e
        @abort_reason = "permanent error: #{e.message}"
        @git&.reset_hard unless @pending_commit_failure
        @logger.log("orchestrator:abort", reason: @abort_reason, permanent: true)
      rescue => e
        message = e.message
        @abort_reason = "fatal: #{message}"
        @git&.reset_hard unless @pending_commit_failure
        @logger.log("orchestrator:fatal", error: e.class.to_s, message: message)
      ensure
        finalize_run
      end

      private

      # :reek:TooManyStatements -- the loop body is the iteration lifecycle in
      # its literal execution order; splitting it further would hide that order.
      def main_loop
        loop do
          break if @stop_requested

          handle_blocking_decisions
          break if @stop_requested

          @stop_conditions.before?

          @run.iteration += 1
          iteration = @run.iteration
          @logger.log("iteration:start", iteration: iteration)
          progress "iteration #{iteration} (#{@config.model})..."

          result = execute_iteration

          if result.success?
            handle_success(result)
          else
            handle_failure(result)
          end

          persist_run_state
          @stop_conditions.after?
          break if @stop_requested
        end
      end

      def finalize_run
        if @run
          @logger.log("orchestrator:end",
                      iterations: @run.iteration, commits: @run.commits,
                      input_tokens: @run.input_tokens, output_tokens: @run.output_tokens,
                      abort_reason: @abort_reason, elapsed: @run.elapsed_seconds.round(1))
          @logger.close
          ExitSummary.new(@run, @config, abort_reason: @abort_reason).print
        else
          @logger.close
          progress(@abort_reason) if @abort_reason
        end
      end

      # :reek:TooManyStatements -- one-time run bootstrap, each step required
      # in this order (branch, run dir, Run record, logger, notes, collaborators).
      def setup_run
        @git = CommitManager.new
        ensure_head!

        run_id     = Run.generate_id
        branch     = Run.branch_name(@objective)
        run_dir    = Pathname.new(@config.run_dir).join("runs", run_id)

        @git.create_branch(branch)
        base_commit = @git.head_sha
        @git.add_to_local_exclude(@config.run_dir)

        run_dir.mkpath

        @run = Run.new(run_id: run_id, objective: @objective, branch: branch,
                       base_commit: base_commit, notes_path: run_dir.join("notes.md"),
                       log_path: run_dir.join("run.log"), run_dir: run_dir)

        @logger.open(@run.log_path)

        @notes = NotesManager.new(@run.notes_path)
        @notes.setup(@run)

        build_collaborators
        persist_run_state
      end

      # Resume a prior run from its run.json — enables external scheduling (cron):
      # each tick re-enters the loop on the same branch and advances or re-pauses.
      # :reek:TooManyStatements -- mirrors #setup_run's bootstrap order for the
      # resume path.
      def setup_resume
        @git = CommitManager.new
        ensure_head!

        state_path = Pathname.new(@config.run_dir).join("runs", @resume_run_id, "run.json")
        raise AbortError, "no resumable run at #{state_path}" unless state_path.exist?

        @run       = Run.load(state_path)
        @objective = @run.objective
        branch     = @run.branch
        @git.checkout_branch(branch)

        @logger.open(@run.log_path)
        @notes = NotesManager.new(@run.notes_path)  # append — do NOT re-setup (would clobber history)

        build_collaborators

        @logger.log("orchestrator:resume", run_id: @run.run_id, iteration: @run.iteration,
                                           branch: branch, model: @config.model)
        progress "resumed run #{@run.run_id} at iteration #{@run.iteration} → branch #{branch}"
      end

      # Shared setup used by both a fresh run and a resume.
      def build_collaborators
        @builder         = PromptBuilder.new(@config)
        @backoff         = Backoff.new
        @stop_conditions = StopConditions.new(@config, @run)
        @evaluator       = Evals.build(@config, git: @git)
        @decisions       = DecisionManager.new(@run.decisions_path)
        @decisions.setup
      end

      def ensure_head!
        return if @git.head_exists?

        raise AbortError, "No commits found. robot-to requires at least one commit. " \
                          "Run: git commit --allow-empty -m 'initial'"
      end

      # If a blocking decision is unresolved, either wait for a human (wait mode)
      # or stop the run so it can be resumed later (exit mode).
      def handle_blocking_decisions
        return unless @config.decisions_enabled?
        return unless @decisions&.blocking_pending?

        pending = @decisions.blocking_pending
        @logger.log("decision:blocking", count: pending.size, mode: @config.decision_mode)

        if @config.decision_mode.to_s == "exit"
          persist_run_state
          paths = pending.map(&:path).join("\n  ")
          raise AbortError, "awaiting human decision — resolve then resume:\n  #{paths}\n  " \
                            "robot-to --resume #{@run.run_id}"
        else
          wait_for_decisions(pending)
        end
      end

      # Poll the decision files until every blocking decision is resolved, the run
      # is signaled to stop, or decision_timeout elapses.
      # :reek:TooManyStatements -- the three exit conditions (stopped, resolved,
      # timed out) must all be checked inside one poll loop.
      def wait_for_decisions(pending)
        progress "awaiting human decision on #{pending.size} item(s):"
        pending.each { |d| progress "  #{d.path}" }
        @logger.log("decision:wait:start", count: pending.size)
        timeout  = @config.decision_timeout
        deadline = timeout ? monotonic + timeout.to_i : nil

        loop do
          return if @stop_requested

          @backoff.sleep_seconds(@config.decision_wait_poll)
          return if @stop_requested
          break unless @decisions.blocking_pending?

          if deadline && monotonic >= deadline
            raise AbortError, "awaiting human decision (timed out after #{timeout}s)"
          end
        end

        @logger.log("decision:wait:resolved")
        progress "decision resolved — resuming"
      end

      def execute_iteration
        run_agent_iteration
      rescue PermanentError
        raise
      rescue => e
        raise PermanentError, "API authentication failed: #{e.message}" if auth_error?(e)

        record_iteration_error(e)
        retry if retry_after_backoff?
        raise
      end

      # The happy path: build a fresh robot, run it, and return its submitted
      # result (or a not-submitted marker).
      # :reek:TooManyStatements -- one call per lifecycle step (reset counters,
      # build prompt/robot, run, nudge, persist decisions, return result).
      def run_agent_iteration
        @accounted_in = @accounted_out = 0
        @submit_tool   = Tools::SubmitResult.new
        @decision_tool = @config.decisions_enabled? ? Tools::RequestDecision.new : nil
        @injected_decisions = @config.decisions_enabled? ? @decisions.resolved_open : []

        prompt = @builder.build(@run, @notes.read, workspace: workspace_digest,
                                                   pending_commit_failure: @pending_commit_failure,
                                                   resolved_decisions: @injected_decisions)
        @robot = build_robot(@submit_tool, prompt)

        @logger.log("agent:run:start", iteration: @run.iteration)
        run_robot_with_interrupt(@robot)
        @logger.log("agent:run:end", iteration: @run.iteration)

        nudge_for_missing_submit(@robot, @submit_tool) if @submit_tool.captured_result.nil?

        persist_raised_decisions
        @submit_tool.captured_result || IterationResult.not_submitted
      end

      # Write each decision the robot raised this iteration to its own file and
      # record it in notes.md. Blocking ones are caught at the top of the next
      # loop pass by handle_blocking_decisions.
      def persist_raised_decisions
        return unless @decision_tool

        iteration = @run.iteration
        @decision_tool.captured_requests.each do |req|
          decision = @decisions.record(**req, iteration: iteration)
          @notes.append_decision(decision, iteration)
          @logger.log("decision:raised", id: decision.id, blocking: decision.blocking,
                                          question: decision.question)
          progress "iteration #{iteration} raised decision: #{decision.question}"
        end
      end

      # R3: tracked files give the robot the project layout up front, so it does
      # not re-explore the workspace every iteration. nil when unavailable.
      def workspace_digest
        files = @git.tracked_files
        files.empty? ? nil : files
      rescue StandardError
        nil
      end

      # Roll back the working tree, record the failure in notes, and bump the
      # consecutive failure/error counters.
      def record_iteration_error(e)
        @logger.log("agent:run:error", iteration: @run.iteration,
                                       error: e.class.to_s, message: e.message)
        @git.reset_hard unless @pending_commit_failure
        @notes.append_error(e, @run.iteration)
        @run.consecutive_failures += 1
        @run.consecutive_errors   += 1
        @run.iterations_since_improvement += 1
      end

      # True when the iteration should be retried — within the retry budget and
      # not stopping. Sleeps out the backoff as a side effect before returning.
      def retry_after_backoff?
        errors = @run.consecutive_errors
        return false unless errors <= @config.max_retries && !@stop_requested

        @logger.log("backoff:start", consecutive_errors: errors)
        @backoff.sleep_for(errors)
        @logger.log("backoff:end")
        true
      end

      # A robot that ends its turn without calling submit_result is the
      # "thinks but doesn't act" degenerate case. Rather than burning the
      # iteration as a failure, re-prompt the same robot (preserving its chat
      # context) up to max_submit_nudges times to call submit_result.
      def nudge_for_missing_submit(robot, tool)
        @config.max_submit_nudges.times do |i|
          break if @stop_requested

          attempt = i + 1
          @logger.log("agent:nudge", iteration: @run.iteration, attempt: attempt)
          progress "iteration #{@run.iteration}: no result submitted — " \
                   "nudging (#{attempt}/#{@config.max_submit_nudges})"
          run_robot_with_interrupt(robot, SUBMIT_NUDGE)
          break if tool.captured_result
        end
      end

      def handle_success(result)
        score = evaluate
        result, score = repair_until_gate(result, score) unless score.gate_ok?
        return handle_gate_failure(result, score) unless score.gate_ok?
        return handle_no_improvement(result, score) if reject_no_improvement?(score)

        commit_improvement(result, score)
      end

      # A change that passes the gate but does not beat the parent is discarded so
      # the branch descends monotonically. Disabled by --no-require-improvement.
      def reject_no_improvement?(score)
        @config.require_improvement? && !score.improved?
      end

      # The commit path: record the win, then let the eval (not the robot) decide
      # whether the objective is met.
      def commit_improvement(result, score)
        @notes.append_success(result, @run.iteration)
        attempt_commit(result)
        record_improvement(score)
        close_injected_decisions
        stop_if_target_met(score, result)
        nil
      end

      def record_improvement(score)
        @run.last_score_value = score.value unless score.value.nil?
        @run.iterations_since_improvement = 0
        @run.consecutive_failures = 0
        @run.consecutive_errors   = 0
      end

      # Orchestrator-owned stop: the eval's measurable target supersedes the
      # robot's self-reported should_fully_stop; --stop-when remains as a fallback.
      def stop_if_target_met(score, result)
        raise AbortError, "target met: #{score.detail}" if score.met_target?

        @stop_conditions.stop_when_met?(result)
        nil
      end

      def handle_no_improvement(result, score)
        iteration = @run.iteration
        detail    = score.detail
        @git.reset_hard unless @pending_commit_failure
        @notes.append_no_improvement(result, detail, iteration)
        # A non-improving iteration is valid work that just wasn't better -- NOT a
        # failure. It counts toward the plateau (diminishing-returns) stop only, so
        # it must NOT trip max_consecutive_failures, which is for the robot being
        # genuinely broken (errors, gate failures, no submit). Conflating the two
        # throttles legitimate exploration -- especially for prose, where "same"
        # verdicts are common and normal.
        @run.iterations_since_improvement += 1
        @run.consecutive_errors = 0
        @logger.log("iteration:no_improvement", iteration: iteration, detail: detail)
        progress "iteration #{iteration} no improvement (#{detail}) — rolled back"
      end

      # A resolved decision that was injected into this successful iteration has
      # now been acted on and committed, so close it — it should not be re-fed to
      # future iterations. Failed iterations leave it open for the next pass.
      def close_injected_decisions
        return if @injected_decisions.nil? || @injected_decisions.empty?

        @injected_decisions.each { |d| @decisions.close(d) }
        @injected_decisions = []
      end

      # Independent gate: the robot claimed success, but the deciding authority is
      # the configured Eval, not the robot. Always returns a Score (never nil) --
      # Evals::Null (the default) reports gate_ok, so behavior matches "no gate".
      def evaluate
        ctx = Evals::Context.new(work_dir: Dir.pwd, previous_ref: @git.head_sha,
                                 previous_value: @run.last_score_value,
                                 objective: @objective, iteration: @run.iteration)
        score = @evaluator.score(ctx)
        @logger.log("eval", iteration: @run.iteration, gate: score.gate_ok,
                            improved: score.improved, value: score.value,
                            met_target: score.met_target, detail: score.detail)
        score
      end

      # :reek:TooManyStatements -- rollback + record + report, one statement each.
      def handle_gate_failure(result, score)
        iteration = @run.iteration
        @git.reset_hard unless @pending_commit_failure
        @notes.append_verify_failure(result, score.output.to_s, iteration)
        @run.consecutive_failures += 1
        @run.consecutive_errors    = 0
        @run.iterations_since_improvement += 1
        @logger.log("iteration:gate_failure", iteration: iteration)
        progress "iteration #{iteration} verification failed — rolled back"
        nil
      end

      # R2: when the gate fails on a claimed success, hand the failure output back
      # to the SAME robot (its chat + the working tree are intact) and let it fix
      # the code, re-verifying after each attempt. Only fall back to a full
      # rollback once the repair budget is spent — a near-miss no longer discards
      # all the work, and nothing commits until the gate is green.
      # :reek:TooManyStatements -- repair/re-verify loop with its own rescue;
      # each statement is a distinct step of one repair attempt.
      def repair_until_gate(result, score)
        budget    = @config.max_verify_repairs.to_i
        iteration = @run.iteration
        return [result, score] if budget.zero? || @robot.nil?

        budget.times do |i|
          break if @stop_requested

          @logger.log("eval:repair", iteration: iteration, attempt: i + 1)
          progress "iteration #{iteration}: verification failed — repairing (#{i + 1}/#{budget})"
          begin
            run_robot_with_interrupt(@robot, repair_prompt(score))
          rescue StandardError => e
            @logger.log("eval:repair_error", iteration: iteration, message: e.message)
            break
          end
          result = @submit_tool.captured_result || result
          score  = evaluate
          gate_ok = score.gate_ok?
          break if gate_ok
        end

        [result, score]
      end

      def repair_prompt(score)
        gate   = @config.verify_command.to_s.strip
        target = gate.empty? ? "the verification gate" : "`#{gate}`"
        <<~MSG
          Your changes did NOT pass verification. Running #{target} failed:

          #{score.output}

          Fix the code so it passes, then call submit_iteration_result again.
          Build on the work already in the project — do not start over.
        MSG
      end

      def handle_failure(result)
        iteration = @run.iteration
        @git.reset_hard unless @pending_commit_failure
        @notes.append_failure(result, iteration)
        @run.consecutive_failures += 1
        @run.consecutive_errors = 0
        @run.iterations_since_improvement += 1
        @logger.log("iteration:failure", iteration: iteration, summary: result.summary)
        progress "iteration #{iteration} failed: #{result.summary}"
      end

      # :reek:TooManyStatements -- commit path plus its own CommitFailedError
      # rescue; the two branches (success, queue-for-repair) are each tight.
      def attempt_commit(result)
        iteration = @run.iteration
        @git.add_all
        return unless @git.staged?

        message = commit_message(result)
        @git.commit(message)
        @run.commits += 1
        @pending_commit_failure = nil
        @logger.log("commit:success", iteration: iteration, message: message)
        progress "iteration #{iteration} committed: #{message}"
      rescue CommitFailedError => e
        @pending_commit_failure = e
        @run.consecutive_failures += 1
        @run.consecutive_errors = 0
        @logger.log("commit:failed", iteration: iteration, output: e.output)
        progress "iteration #{iteration} commit failed — queued for repair"
      end

      # :reek:FeatureEnvy -- formatting the commit message from result's own fields.
      def commit_message(result)
        if @config.commit_format == "conventional"
          type  = result.respond_to?(:type)  ? (result.type || "chore") : "chore"
          scope = result.respond_to?(:scope) ? result.scope : nil
          tag   = scope ? "#{type}(#{scope})" : type
          "#{tag}: #{result.summary}"
        else
          "robot-to #{@run.iteration}: #{result.summary}"
        end
      end

      # Persist run state so an external scheduler can --resume this run.
      def persist_run_state
        return unless @run

        AtomicFile.write(@run.state_path, JSON.pretty_generate(@run.to_h))
      rescue SystemCallError => e
        @logger.log("run_state:write_failed", message: e.message)
      end

      def build_robot(submit_tool, system_prompt)
        robot = RobotLab.build(
          name: "robot-to-#{@run.run_id}-#{@run.iteration}",
          system_prompt: system_prompt,
          local_tools: iteration_tools(submit_tool),
          provider: @config.provider&.to_sym,
          model: @config.model,
          max_tool_rounds: @config.max_tool_rounds,
          on_content: (@config.stream? ? token_tracker : nil)
        )
        Guards.install(robot, run: @run, except: guard_exclusions) if @config.local_guards?
        install_grader_lock(robot)
        robot
      end

      # Always-on (independent of --local-guards): lock the eval's grader
      # artifacts so the robot cannot edit the criteria it is scored against.
      def install_grader_lock(robot)
        paths = grader_lock_paths
        robot.on(Guards::GraderLock, context: { paths: paths }) unless paths.empty?
      end

      def grader_lock_paths
        (Array(@evaluator&.protected_paths) + Array(@config.protect_paths))
          .flat_map { |glob| Dir.glob(glob) }
          .map { |path| File.expand_path(path) }
          .uniq
      end

      # Guards to skip when installing the local-guards set. Dropping WriteGuard
      # lets the robot overwrite files it is iteratively refining.
      def guard_exclusions
        @config.write_guard ? [] : [Guards::WriteGuard]
      end

      # Submit tool is always first (callers read tools.first). The decision tool
      # follows when decisions are enabled. When local_guards is on, the robot
      # also gets the built-in workspace tools the guards protect.
      def iteration_tools(submit_tool)
        tools = [submit_tool]
        tools << @decision_tool if @decision_tool
        return tools unless @config.local_guards?

        tools + [Tools::Read.new, Tools::Write.new, Tools::Edit.new, Tools::Bash.new]
      end

      def token_tracker
        lambda do |chunk|
          @run.input_tokens  += chunk.input_tokens.to_i
          @run.output_tokens += chunk.output_tokens.to_i

          return unless @stop_conditions.token_limit_exceeded?

          @stop_requested = true
          @backoff.interrupt!
          @runner_thread&.raise(Interrupt)
        end
      end

      # :reek:TooManyStatements -- runs the robot on its own Thread so a signal
      # can interrupt it; each statement manages that thread's lifecycle.
      def run_robot_with_interrupt(robot, task = @objective)
        thread_error = nil
        result = nil
        @runner_thread = Thread.new do
          # tools: :inherit is REQUIRED — RobotLab::Robot#run defaults to
          # tools: :none (its prompt-driven tool selector sends nothing unless
          # told). Without this the robot receives zero tools and can never call
          # submit_iteration_result / read / write, so every iteration fails.
          result = robot.run(task, tools: :inherit)
        rescue Interrupt
          # killed by signal handler — main loop checks @stop_requested
        rescue => e
          thread_error = e
        end
        @runner_thread.join
        @runner_thread = nil
        raise thread_error if thread_error

        # Streaming runs account tokens per-chunk via token_tracker; non-streaming
        # runs (required for local models whose tool calls don't survive the
        # OpenAI-compatible stream) account them from the robot instead.
        account_tokens(robot) unless @config.stream?
        result
      end

      # R4: account a non-streaming run's tokens from the robot's CUMULATIVE
      # totals (which include every tool round), not just the final response's
      # usage. @accounted_* is reset per iteration (fresh robot starts at zero),
      # so adding the delta accumulates correctly across the initial run, nudges,
      # and repairs without double-counting. Trips the stop flag on budget.
      def account_tokens(robot)
        return unless robot.respond_to?(:total_input_tokens)

        in_total  = robot.total_input_tokens.to_i
        out_total = robot.total_output_tokens.to_i
        @run.input_tokens  += in_total - @accounted_in
        @run.output_tokens += out_total - @accounted_out
        @accounted_in  = in_total
        @accounted_out = out_total
        @stop_requested = true if @stop_conditions.token_limit_exceeded?
      end

      def install_signal_handlers
        trap("INT") do
          @stop_requested = true
          @backoff.interrupt!
          @runner_thread&.raise(Interrupt)
        end
        trap("TERM") do
          @stop_requested = true
          @backoff.interrupt!
          @runner_thread&.raise(Interrupt)
        end
      end

      # Live progress to stderr. Uses $stderr.puts rather than Kernel#warn,
      # which is silenced when Ruby warnings are disabled ($VERBOSE is nil —
      # common under `bundle exec`), hiding progress from the user.
      def progress(msg)
        $stderr.puts "robot-to: #{msg}"
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def auth_error?(e)
        klass = e.class.name.to_s
        klass.include?("Unauthorized") ||
          klass.include?("Authentication") ||
          e.message.to_s.match?(/invalid api key|unauthorized|authentication failed/i)
      end
    end
  end
end
