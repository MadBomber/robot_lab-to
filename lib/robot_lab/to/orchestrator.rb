# frozen_string_literal: true

require "securerandom"

module RobotLab
  module To
    # Main autonomous loop.
    #
    # Creates a new robot per iteration, reads the iteration result from SubmitResultTool,
    # then commits, rolls back, or queues repair depending on the outcome.
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

      def initialize(objective, config)
        @objective              = objective
        @config                 = config
        @stop_requested         = false
        @abort_reason           = nil
        @pending_commit_failure = nil
        @logger                 = JsonlLogger.new  # buffers pre-open events
        @run                    = nil
        @git                    = nil
        @runner_thread          = nil
        @verifier               = nil
      end

      def run
        setup_run
        install_signal_handlers
        @logger.log("orchestrator:start", run_id: @run.run_id, objective: @objective,
                                          branch: @run.branch, model: @config.model)
        progress "run #{@run.run_id} → branch #{@run.branch}"
        main_loop
      rescue AbortError => e
        @abort_reason = e.reason
        @logger.log("orchestrator:abort", reason: @abort_reason)
      rescue PermanentError => e
        @abort_reason = "permanent error: #{e.message}"
        @git&.reset_hard unless @pending_commit_failure
        @logger.log("orchestrator:abort", reason: @abort_reason, permanent: true)
      rescue => e
        @abort_reason = "fatal: #{e.message}"
        @git&.reset_hard unless @pending_commit_failure
        @logger.log("orchestrator:fatal", error: e.class.to_s, message: e.message)
      ensure
        finalize_run
      end

      private

      def main_loop
        loop do
          break if @stop_requested

          @stop_conditions.before?

          @run.iteration += 1
          @logger.log("iteration:start", iteration: @run.iteration)
          progress "iteration #{@run.iteration} (#{@config.model})..."

          result = execute_iteration

          if result.success?
            handle_success(result)
          else
            handle_failure(result)
          end

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

      def setup_run
        @git = CommitManager.new

        unless @git.head_exists?
          raise AbortError, "No commits found. robot-to requires at least one commit. " \
                            "Run: git commit --allow-empty -m 'initial'"
        end

        run_id     = Run.generate_id
        branch     = Run.branch_name(@objective)
        run_dir    = Pathname.new(@config.run_dir).join("runs", run_id)
        notes_path = run_dir.join("notes.md")
        log_path   = run_dir.join("run.log")

        @git.create_branch(branch)
        base_commit = @git.head_sha
        @git.add_to_local_exclude(@config.run_dir)

        run_dir.mkpath

        @run = Run.new(run_id: run_id, objective: @objective, branch: branch,
                       base_commit: base_commit, notes_path: notes_path, log_path: log_path)

        @logger.open(log_path)

        @notes   = NotesManager.new(notes_path)
        @notes.setup(@run)

        @builder = PromptBuilder.new(@config)
        @backoff = Backoff.new
        @stop_conditions = StopConditions.new(@config, @run)
        @verifier = build_verifier
      end

      def build_verifier
        cmd = @config.verify_command.to_s.strip
        return nil if cmd.empty?

        Verifier.new(cmd, work_dir: Dir.pwd, timeout: @config.verify_timeout)
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
      def run_agent_iteration
        tool   = Tools::SubmitResult.new
        prompt = @builder.build(@run, @notes.read, pending_commit_failure: @pending_commit_failure)
        robot  = build_robot(tool, prompt)

        @logger.log("agent:run:start", iteration: @run.iteration)
        run_robot_with_interrupt(robot)
        @logger.log("agent:run:end", iteration: @run.iteration)

        nudge_for_missing_submit(robot, tool) if tool.captured_result.nil?

        tool.captured_result || IterationResult.not_submitted
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
      end

      # True when the iteration should be retried — within the retry budget and
      # not stopping. Sleeps out the backoff as a side effect before returning.
      def retry_after_backoff?
        return false unless @run.consecutive_errors <= @config.max_retries && !@stop_requested

        @logger.log("backoff:start", consecutive_errors: @run.consecutive_errors)
        @backoff.sleep_for(@run.consecutive_errors)
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
        verdict = verify_result
        return handle_verify_failure(result, verdict) if verdict && !verdict.passed?

        @notes.append_success(result, @run.iteration)
        attempt_commit(result)
        @run.consecutive_failures = 0
        @run.consecutive_errors   = 0
        @stop_conditions.stop_when_met?(result)
        nil
      end

      # Independent gate: the robot claimed success, but it only counts if the
      # configured verify_command passes. Returns nil when verification is off.
      def verify_result
        return nil unless @verifier

        @logger.log("verify:start", iteration: @run.iteration, command: @config.verify_command)
        verdict = @verifier.run
        @logger.log("verify:#{verdict.passed? ? "pass" : "fail"}", iteration: @run.iteration)
        verdict
      end

      def handle_verify_failure(result, verdict)
        @git.reset_hard unless @pending_commit_failure
        @notes.append_verify_failure(result, verdict.output, @run.iteration)
        @run.consecutive_failures += 1
        @run.consecutive_errors    = 0
        @logger.log("iteration:verify_failure", iteration: @run.iteration)
        progress "iteration #{@run.iteration} verification failed — rolled back"
        nil
      end

      def handle_failure(result)
        @git.reset_hard unless @pending_commit_failure
        @notes.append_failure(result, @run.iteration)
        @run.consecutive_failures += 1
        @run.consecutive_errors = 0
        @logger.log("iteration:failure", iteration: @run.iteration, summary: result.summary)
        progress "iteration #{@run.iteration} failed: #{result.summary}"
      end

      def attempt_commit(result)
        @git.add_all
        return unless @git.staged?

        message = commit_message(result)
        @git.commit(message)
        @run.commits += 1
        @pending_commit_failure = nil
        @logger.log("commit:success", iteration: @run.iteration, message: message)
        progress "iteration #{@run.iteration} committed: #{message}"
      rescue CommitFailedError => e
        @pending_commit_failure = e
        @run.consecutive_failures += 1
        @run.consecutive_errors = 0
        @logger.log("commit:failed", iteration: @run.iteration, output: e.output)
        progress "iteration #{@run.iteration} commit failed — queued for repair"
      end

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
        Guards.install(robot, run: @run) if @config.local_guards?
        robot
      end

      # Submit tool is always first (callers read tools.first). When local_guards
      # is on, the robot also gets the built-in workspace tools the guards
      # protect; otherwise behavior is unchanged (submit-only).
      def iteration_tools(submit_tool)
        return [submit_tool] unless @config.local_guards?

        [submit_tool,
         Tools::Read.new,
         Tools::Write.new,
         Tools::Edit.new,
         Tools::Bash.new]
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

      def run_robot_with_interrupt(robot, task = @objective)
        thread_error = nil
        result = nil
        @runner_thread = Thread.new do
          result = robot.run(task)
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
        # OpenAI-compatible stream) account them from the result instead.
        account_tokens(result) unless @config.stream?
        result
      end

      # Add a non-streaming run's token usage to the run totals and trip the
      # stop flag if the budget is now exhausted (the mid-stream interrupt that
      # token_tracker provides isn't available without streaming).
      def account_tokens(result)
        return unless result

        @run.input_tokens  += result.input_tokens.to_i  if result.respond_to?(:input_tokens)
        @run.output_tokens += result.output_tokens.to_i if result.respond_to?(:output_tokens)
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

      def auth_error?(e)
        klass = e.class.name.to_s
        klass.include?("Unauthorized") ||
          klass.include?("Authentication") ||
          e.message.to_s.match?(/invalid api key|unauthorized|authentication failed/i)
      end
    end
  end
end
