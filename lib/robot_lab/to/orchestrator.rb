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

      def initialize(objective, config)
        @objective              = objective
        @config                 = config
        @stop_requested         = false
        @abort_reason           = nil
        @pending_commit_failure = nil
        @logger                 = JsonlLogger.new  # buffers pre-open events
        @run                    = nil
        @git                    = nil
      end

      def run
        setup_run
        install_signal_handlers
        @logger.log("orchestrator:start", run_id: @run.run_id, objective: @objective,
                                          branch: @run.branch, model: @config.model)
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
          warn "robot-to: #{@abort_reason}" if @abort_reason
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
      end

      def execute_iteration
        tool   = Tools::SubmitResult.new
        prompt = @builder.build(@run, @notes.read, pending_commit_failure: @pending_commit_failure)
        robot  = build_robot(tool, prompt)

        @logger.log("agent:run:start", iteration: @run.iteration)
        robot.run(@objective)
        @logger.log("agent:run:end", iteration: @run.iteration)

        tool.captured_result || IterationResult.not_submitted
      rescue PermanentError
        raise
      rescue => e
        raise PermanentError, "API authentication failed: #{e.message}" if auth_error?(e)

        @logger.log("agent:run:error", iteration: @run.iteration,
                                       error: e.class.to_s, message: e.message)
        @git.reset_hard unless @pending_commit_failure
        @notes.append_error(e, @run.iteration)
        @run.consecutive_failures += 1
        @run.consecutive_errors   += 1

        if @run.consecutive_errors <= @config.max_retries && !@stop_requested
          @logger.log("backoff:start", consecutive_errors: @run.consecutive_errors)
          @backoff.sleep_for(@run.consecutive_errors)
          @logger.log("backoff:end")
          retry
        end
        raise
      end

      def handle_success(result)
        @notes.append_success(result, @run.iteration)
        attempt_commit(result)
        @run.consecutive_failures = 0
        @run.consecutive_errors   = 0
        @stop_conditions.stop_when_met?(result)
        nil
      end

      def handle_failure(result)
        @git.reset_hard unless @pending_commit_failure
        @notes.append_failure(result, @run.iteration)
        @run.consecutive_failures += 1
        @run.consecutive_errors = 0
        @logger.log("iteration:failure", iteration: @run.iteration, summary: result.summary)
      end

      def attempt_commit(result)
        @git.add_all
        return unless @git.staged?

        message = commit_message(result)
        @git.commit(message)
        @run.commits += 1
        @pending_commit_failure = nil
        @logger.log("commit:success", iteration: @run.iteration, message: message)
      rescue CommitFailedError => e
        @pending_commit_failure = e
        @run.consecutive_failures += 1
        @run.consecutive_errors = 0
        @logger.log("commit:failed", iteration: @run.iteration, output: e.output)
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
        RobotLab.build(
          name: "robot-to-#{@run.run_id}-#{@run.iteration}",
          system_prompt: system_prompt,
          tools: [submit_tool],
          model: @config.model,
          max_tool_rounds: @config.max_tool_rounds,
          on_content: token_tracker
        )
      end

      def token_tracker
        lambda do |_content, usage|
          return unless usage

          @run.input_tokens  += usage[:input_tokens].to_i
          @run.output_tokens += usage[:output_tokens].to_i

          return unless @stop_conditions.token_limit_exceeded?

          @stop_requested = true
          @backoff.interrupt!
        end
      end

      def install_signal_handlers
        trap("INT")  do
          @stop_requested = true
          @backoff.interrupt!
        end
        trap("TERM") do
          @stop_requested = true
          @backoff.interrupt!
        end
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
