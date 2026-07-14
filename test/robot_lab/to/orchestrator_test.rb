# frozen_string_literal: true

require "test_helper"
require "open3"

module RobotLab
  module To
    class OrchestratorTest < Minitest::Test
      # Robot that always calls submit_iteration_result (success or failure).
      class FakeRobot
        def initialize(tool, success: true, write_file: nil)
          @tool       = tool
          @success    = success
          @write_file = write_file
        end

        def run(_objective, **)
          File.write(@write_file, "robot change #{rand}") if @write_file
          @tool.execute(
            success: @success,
            summary: @success ? "made progress" : "nothing useful",
            key_changes: @write_file ? [@write_file] : [],
            key_learnings: []
          )
        end
      end

      # Robot that never calls submit_iteration_result.
      class SilentRobot
        def initialize(_tool, **) = nil
        def run(_objective, **) = nil
      end

      # Silent on the first run; submits (with a file change) only when nudged.
      class NudgeThenSubmitRobot
        def initialize(tool, write_file:)
          @tool       = tool
          @write_file = write_file
          @calls      = 0
        end

        def run(_task, **)
          @calls += 1
          return nil if @calls < 2

          File.write(@write_file, "recovered #{rand}")
          @tool.execute(success: true, summary: "recovered after nudge",
                        key_changes: [@write_file], key_learnings: [])
        end
      end

      # Robot that sets should_fully_stop on the first call.
      class StopRobot
        def initialize(tool, **) = @tool = tool

        def run(_objective, **)
          @tool.execute(success: true, summary: "objective met",
                        key_changes: [], key_learnings: [], should_fully_stop: true)
        end
      end

      # Submits success, but its first attempt fails verification; the repair
      # re-run (driven by the orchestrator) fixes it so verification then passes.
      class RepairRobot
        def initialize(tool, write_file:)
          @tool = tool
          @write_file = write_file
          @calls = 0
        end

        def run(_task, **)
          @calls += 1
          File.write(@write_file, @calls >= 2 ? "good" : "bad")
          @tool.execute(success: true, summary: "attempt #{@calls}",
                        key_changes: [@write_file], key_learnings: [])
        end
      end

      # Raises a decision (blocking or not) then submits success with a file change.
      # Built with both the submit tool (local_tools[0]) and decision tool (local_tools[1]).
      class DecisionRobot
        def initialize(submit, decision, blocking:, write_file:)
          @submit = submit
          @decision = decision
          @blocking = blocking
          @write_file = write_file
        end

        def run(_task, **)
          File.write(@write_file, "work #{rand}")
          @decision.execute(question: "404 or 410?", situation: "public API contract",
                            options: %w[404 410], recommendation: "410 Gone", blocking: @blocking)
          @submit.execute(success: true, summary: "did work",
                          key_changes: [@write_file], key_learnings: [])
        end
      end

      # Writes an increasing score each iteration so every iteration improves.
      class ImprovingRobot
        def initialize(tool, work:, score:, counter:)
          @tool    = tool
          @work    = work
          @score   = score
          @counter = counter
        end

        def run(_task, **)
          @counter[0] += 1
          File.write(@work, "change #{@counter[0]}")
          File.write(@score, (@counter[0] * 10).to_s)
          @tool.execute(success: true, summary: "iter #{@counter[0]}",
                        key_changes: [@work], key_learnings: [])
        end
      end

      def setup
        @tmpdir = Dir.mktmpdir
        system("git", "-C", @tmpdir, "init", "-q")
        system("git", "-C", @tmpdir, "config", "user.email", "test@test.com")
        system("git", "-C", @tmpdir, "config", "user.name", "Test")
        File.write(File.join(@tmpdir, "README.md"), "init")
        system("git", "-C", @tmpdir, "add", "-A")
        system("git", "-C", @tmpdir, "commit", "-m", "init", out: File::NULL, err: File::NULL)
      end

      def teardown
        FileUtils.rm_rf(@tmpdir)
      end

      def stub_build(robot_class, **robot_opts, &)
        fake = ->(**kw) { robot_class.new(kw[:local_tools].first, **robot_opts) }
        RobotLab.stub(:build, fake, &)
      end

      def run_orch(objective: "test objective", **config_opts)
        config = Config.new(max_iterations: 1, **config_opts)
        Dir.chdir(@tmpdir) do
          Orchestrator.new(objective, config).run
        end
      end

      def git_log_count
        out, = Open3.capture3("git", "-C", @tmpdir, "log", "--oneline")
        out.lines.count
      end

      # --- Phase 2: Evals scoring (improvement gate, target, plateau) ---

      def test_improving_score_commits_each_iteration
        work    = File.join(@tmpdir, "work.txt")
        score   = File.join(@tmpdir, "score.txt")
        counter = [0]
        fake = ->(**kw) { ImprovingRobot.new(kw[:local_tools].first, work: work, score: score, counter: counter) }
        RobotLab.stub(:build, fake) do
          run_orch(max_iterations: 3, eval_measure: "cat #{score}")
        end
        assert_equal 4, git_log_count, "each improving iteration commits (init + 3)"
      end

      def test_flat_score_rolls_back_after_first_commit
        path = File.join(@tmpdir, "work.txt")
        stub_build(FakeRobot, write_file: path) do
          run_orch(max_iterations: 2, eval_measure: "echo 50", max_consecutive_failures: 10)
        end
        assert_equal 2, git_log_count, "a non-improving iteration is rolled back, not committed"
      end

      def test_no_require_improvement_commits_flat_scores
        path = File.join(@tmpdir, "work.txt")
        stub_build(FakeRobot, write_file: path) do
          run_orch(max_iterations: 2, eval_measure: "echo 50",
                   require_improvement: false, max_consecutive_failures: 10)
        end
        assert_equal 3, git_log_count, "with the gate off, flat-scoring iterations still commit"
      end

      def test_target_met_stops_the_run
        path   = File.join(@tmpdir, "work.txt")
        builds = [0]
        fake = lambda do |**kw|
          builds[0] += 1
          FakeRobot.new(kw[:local_tools].first, write_file: path)
        end
        RobotLab.stub(:build, fake) do
          run_orch(max_iterations: 5, eval_measure: "echo 95", eval_target: 90)
        end
        assert_equal 1, builds[0], "the run stops once the eval target is met"
      end

      def test_grader_lock_installed_when_paths_protected
        Dir.mktmpdir do |dir|
          spec = File.join(dir, "outline.md")
          File.write(spec, "x")
          orch = Orchestrator.new("obj", Config.new(protect_paths: [spec]))
          orch.instance_variable_set(:@evaluator, Evals::Null.new)
          calls = []
          robot = Object.new
          robot.define_singleton_method(:on) { |guard, **kw| calls << [guard, kw] }
          orch.send(:install_grader_lock, robot)
          assert_equal 1, calls.size
          assert_equal Guards::GraderLock, calls.first.first
          assert_equal [File.expand_path(spec)], calls.first.last[:context][:paths]
        end
      end

      def test_grader_lock_skipped_when_no_protected_paths
        orch = Orchestrator.new("obj", Config.new)
        orch.instance_variable_set(:@evaluator, Evals::Null.new)
        called = false
        robot = Object.new
        robot.define_singleton_method(:on) { |*, **| called = true }
        orch.send(:install_grader_lock, robot)
        refute called
      end

      # Build a robot through the orchestrator's real build_robot (no LLM call —
      # RobotLab.build constructs offline; the network is only touched on #run).
      def built_robot(submit_tool, **config_opts)
        config = Config.new(model: "test-model", provider: :openai, **config_opts)
        orch   = Orchestrator.new("objective", config)
        robot  = nil
        stub_run do |run, _dir|
          orch.instance_variable_set(:@run, run)
          robot = orch.send(:build_robot, submit_tool, "sys")
        end
        robot
      end

      # Regression: build_robot once passed tool instances via `tools:`, which
      # Robot.new treats as a name-allowlist filter — so the submit tool never
      # reached the model and every iteration failed as "did not submit". The
      # instances must go through `local_tools:`.
      def test_build_robot_attaches_submit_tool_via_local_tools
        submit = Tools::SubmitResult.new
        assert_includes built_robot(submit).local_tools, submit,
                        "submit tool must be attached via local_tools: so the model can call it"
      end

      def test_build_robot_attaches_only_submit_without_local_guards
        submit = Tools::SubmitResult.new
        assert_equal [submit], built_robot(submit, local_guards: false).local_tools
      end

      def test_build_robot_attaches_file_tools_when_local_guards_enabled
        submit = Tools::SubmitResult.new
        tools  = built_robot(submit, local_guards: true).local_tools
        assert_includes tools, submit
        assert_equal %w[bash edit read write], (tools - [submit]).map(&:name).sort
      end

      def test_success_without_file_changes_makes_no_commit
        stub_build(FakeRobot) { run_orch }
        assert_equal 1, git_log_count
      end

      def test_success_with_file_changes_makes_commit
        stub_build(FakeRobot, write_file: File.join(@tmpdir, "change.rb")) do
          run_orch
        end
        assert_equal 2, git_log_count
      end

      def test_failure_result_makes_no_commit
        stub_build(FakeRobot, success: false) { run_orch }
        assert_equal 1, git_log_count
      end

      def test_nil_result_treated_as_failure_and_increments_counter
        stub_build(SilentRobot, max_consecutive_failures: 1) { run_orch }
        assert_equal 1, git_log_count
      end

      def test_nudge_recovers_missing_submit_and_commits
        path = File.join(@tmpdir, "recovered.rb")
        # Default max_submit_nudges (1): silent first run, submits on the nudge.
        stub_build(NudgeThenSubmitRobot, write_file: path) { run_orch }
        assert_equal 2, git_log_count
      end

      def test_no_nudge_when_disabled_treats_missing_submit_as_failure
        path = File.join(@tmpdir, "recovered.rb")
        stub_build(NudgeThenSubmitRobot, write_file: path) do
          run_orch(max_submit_nudges: 0, max_consecutive_failures: 1)
        end
        assert_equal 1, git_log_count
      end

      def test_verify_pass_allows_commit
        path = File.join(@tmpdir, "feature.rb")
        stub_build(FakeRobot, write_file: path) do
          run_orch(verify_command: "true")
        end
        assert_equal 2, git_log_count
      end

      def test_verify_failure_rolls_back_and_blocks_commit
        path = File.join(@tmpdir, "feature.rb")
        stub_build(FakeRobot, write_file: path) do
          run_orch(verify_command: "exit 1", max_consecutive_failures: 1)
        end
        assert_equal 1, git_log_count
        refute File.exist?(path), "verify failure should roll back the robot's changes"
      end

      def test_repair_in_place_fixes_verify_failure_then_commits
        path = File.join(@tmpdir, "marker.txt")
        stub_build(RepairRobot, write_file: path) do
          run_orch(verify_command: "grep -q good marker.txt")
        end
        assert_equal 2, git_log_count, "the repaired iteration should commit"
        assert_equal "good", File.read(path)
      end

      def test_max_verify_repairs_zero_disables_repair
        path = File.join(@tmpdir, "marker.txt")
        stub_build(RepairRobot, write_file: path) do
          run_orch(verify_command: "grep -q good marker.txt",
                   max_verify_repairs: 0, max_consecutive_failures: 1)
        end
        assert_equal 1, git_log_count, "with no repair budget, verify failure rolls back"
      end

      def test_account_tokens_accumulates_robot_cumulative_delta
        config = Config.new(stream: false)
        stub_run do |run, _dir|
          orch = Orchestrator.new("obj", config)
          orch.instance_variable_set(:@run, run)
          orch.instance_variable_set(:@stop_conditions, StopConditions.new(config, run))
          counter = Struct.new(:total_input_tokens, :total_output_tokens)

          orch.send(:account_tokens, counter.new(100, 40))
          assert_equal 100, run.input_tokens
          assert_equal 40, run.output_tokens

          # cumulative grows; only the delta is added
          orch.send(:account_tokens, counter.new(160, 70))
          assert_equal 160, run.input_tokens
          assert_equal 70, run.output_tokens
        end
      end

      def test_max_iterations_stops_loop
        call_count = 0
        counting_build = lambda do |**kw|
          call_count += 1
          FakeRobot.new(kw[:local_tools].first)
        end
        config = Config.new(max_iterations: 3)
        RobotLab.stub(:build, counting_build) do
          Dir.chdir(@tmpdir) { Orchestrator.new("test", config).run }
        end
        assert_equal 3, call_count
      end

      def test_consecutive_failures_abort
        config = Config.new(max_consecutive_failures: 2)
        call_count = 0
        counting_build = lambda do |**kw|
          call_count += 1
          FakeRobot.new(kw[:local_tools].first, success: false)
        end
        RobotLab.stub(:build, counting_build) do
          Dir.chdir(@tmpdir) { Orchestrator.new("test", config).run }
        end
        assert_equal 2, call_count
      end

      def test_stop_when_aborts_after_robot_sets_flag
        call_count = 0
        counting_build = lambda do |**kw|
          call_count += 1
          StopRobot.new(kw[:local_tools].first)
        end
        config = Config.new(stop_when: "objective met")
        RobotLab.stub(:build, counting_build) do
          Dir.chdir(@tmpdir) { Orchestrator.new("test", config).run }
        end
        assert_equal 1, call_count
      end

      def test_commit_message_uses_summary
        stub_build(FakeRobot, write_file: File.join(@tmpdir, "x.rb")) do
          run_orch
        end
        out, = Open3.capture3("git", "-C", @tmpdir, "log", "--format=%s", "-1")
        assert_includes out, "made progress"
      end

      def test_conventional_commit_format
        stub_build(FakeRobot, write_file: File.join(@tmpdir, "x.rb")) do
          run_orch(commit_format: "conventional")
        end
        out, = Open3.capture3("git", "-C", @tmpdir, "log", "--format=%s", "-1")
        assert_match(/\Achore:/, out)
      end

      def test_notes_file_created_on_run
        stub_build(FakeRobot) { run_orch }
        notes_files = Dir.glob(File.join(@tmpdir, ".robot_lab_to", "runs", "**", "notes.md"))
        refute_empty notes_files
      end

      def test_run_requires_initial_commit
        Dir.mktmpdir do |empty_dir|
          system("git", "-C", empty_dir, "init", "-q")
          Dir.chdir(empty_dir) { Orchestrator.new("test", Config.new).run }
          # AbortError captured internally — no unhandled exception
        end
      end

      def test_permanent_error_aborts_cleanly
        raising_build = lambda do |**_kw|
          r = Object.new
          r.define_singleton_method(:run) { |_| raise PermanentError, "credit exhausted" }
          r
        end
        RobotLab.stub(:build, raising_build) do
          Dir.chdir(@tmpdir) { Orchestrator.new("test", Config.new).run }
        end
      end

      def test_runtime_error_with_no_retries_aborts_cleanly
        raising_build = lambda do |**_kw|
          r = Object.new
          r.define_singleton_method(:run) { |_| raise "network blip" }
          r
        end
        config = Config.new(max_retries: 0)
        RobotLab.stub(:build, raising_build) do
          Dir.chdir(@tmpdir) { Orchestrator.new("test", config).run }
        end
      end

      # Subclass makes backoff instant so retry tests don't sleep 60s.
      class FastOrchestrator < Orchestrator
        private

        def setup_run
          super
          @backoff.define_singleton_method(:sleep_for) { |_| }
        end
      end

      def test_runtime_error_retries_then_aborts
        call_count = 0
        raising_build = lambda do |**_kw|
          call_count += 1
          r = Object.new
          r.define_singleton_method(:run) { |_| raise "flaky" }
          r
        end
        config = Config.new(max_retries: 2)
        RobotLab.stub(:build, raising_build) do
          Dir.chdir(@tmpdir) { FastOrchestrator.new("test", config).run }
        end
        # 1 initial attempt + 2 retries = 3 build calls within execute_iteration
        assert_equal 3, call_count
      end

      MockChunk = Struct.new(:input_tokens, :output_tokens)

      # Robot that calls on_content to simulate token usage reporting.
      class TokenReportingRobot
        def initialize(tool, on_content:, input: 1_000, output: 500)
          @tool       = tool
          @on_content = on_content
          @input      = input
          @output     = output
        end

        def run(_objective, **)
          @on_content.call(MockChunk.new(@input, @output))
          @tool.execute(success: true, summary: "done", key_changes: [], key_learnings: [])
        end
      end

      def test_token_tracker_records_usage_and_stops_on_limit
        call_count = 0
        fake_build = lambda do |**kw|
          call_count += 1
          TokenReportingRobot.new(kw[:local_tools].first, on_content: kw[:on_content],
                                  input: 900, output: 200)
        end
        config = Config.new(max_tokens: 1_000)  # 1100 reported > 1000 limit
        RobotLab.stub(:build, fake_build) do
          Dir.chdir(@tmpdir) { Orchestrator.new("test", config).run }
        end
        assert_equal 1, call_count
      end

      def test_token_tracker_nil_tokens_does_not_crash
        fake_build = lambda do |**kw|
          kw[:on_content].call(MockChunk.new(nil, nil))  # nil tokens in chunk
          FakeRobot.new(kw[:local_tools].first)
        end
        config = Config.new(max_iterations: 1)
        RobotLab.stub(:build, fake_build) do
          Dir.chdir(@tmpdir) { Orchestrator.new("test", config).run }
        end
      end

      # Subclass that makes git commit always fail (patches only the @git singleton).
      class CommitFailOrchestrator < Orchestrator
        private

        def setup_run
          super
          @git.define_singleton_method(:commit) do |_msg|
            raise CommitFailedError.new("gpg failed", output: "sign error")
          end
        end
      end

      def test_commit_failed_error_preserved_for_next_iteration
        write_path = File.join(@tmpdir, "change.rb")
        commit_call = 0
        fake_build = lambda do |**kw|
          commit_call += 1
          FakeRobot.new(kw[:local_tools].first, write_file: write_path)
        end
        config = Config.new(max_iterations: 1)
        RobotLab.stub(:build, fake_build) do
          Dir.chdir(@tmpdir) { CommitFailOrchestrator.new("test", config).run }
        end
        assert_equal 1, commit_call
      end

      # ---- Decision files (async human-in-the-loop) --------------------------

      def latest_run_id
        Dir.glob(File.join(@tmpdir, ".robot_lab_to", "runs", "*"))
           .select { |p| File.directory?(p) }.sort.map { |p| File.basename(p) }.last
      end

      def decisions_for(run_id)
        DecisionManager.new(File.join(@tmpdir, ".robot_lab_to", "runs", run_id, "decisions"))
      end

      # Resolve a decision file the way a human would (edit in place).
      def resolve_file(decision, answer: "go with 410")
        raw = File.read(decision.path)
        File.write(decision.path,
                   raw.sub("status: pending", "status: resolved")
                      .sub("resolution:", "resolution: #{answer}"))
      end

      # Build an orchestrator with the collaborators handle_blocking_decisions
      # needs, without running the full loop.
      def orch_with_decisions(dir, **config_opts)
        orch = Orchestrator.new("obj", Config.new(**config_opts))
        mgr  = DecisionManager.new(dir.join("decisions"))
        mgr.setup
        run  = Run.new(run_id: "rid", objective: "obj", branch: "b", base_commit: "c",
                       notes_path: dir.join("notes.md"), log_path: dir.join("run.log"), run_dir: dir)
        orch.instance_variable_set(:@decisions, mgr)
        orch.instance_variable_set(:@run, run)
        orch.instance_variable_set(:@backoff, Backoff.new)
        orch.instance_variable_set(:@logger, JsonlLogger.new)
        [orch, mgr]
      end

      def test_iteration_tools_includes_decision_tool_when_present
        submit   = Tools::SubmitResult.new
        decision = Tools::RequestDecision.new
        orch     = Orchestrator.new("o", Config.new)
        orch.instance_variable_set(:@decision_tool, decision)
        assert_equal [submit, decision], orch.send(:iteration_tools, submit)
      end

      def test_iteration_tools_with_local_guards_orders_submit_then_decision_then_files
        submit   = Tools::SubmitResult.new
        decision = Tools::RequestDecision.new
        orch     = Orchestrator.new("o", Config.new(local_guards: true))
        orch.instance_variable_set(:@decision_tool, decision)
        tools = orch.send(:iteration_tools, submit)
        assert_equal submit, tools[0]
        assert_equal decision, tools[1]
        assert_equal %w[bash edit read write], tools[2..].map(&:name).sort
      end

      def test_decisions_disabled_attaches_no_decision_tool
        submit = Tools::SubmitResult.new
        orch   = Orchestrator.new("o", Config.new(decisions_enabled: false))
        assert_equal [submit], orch.send(:iteration_tools, submit)
      end

      def test_non_blocking_decision_records_file_and_still_commits
        path  = File.join(@tmpdir, "feature.rb")
        build = ->(**kw) { DecisionRobot.new(kw[:local_tools][0], kw[:local_tools][1], blocking: false, write_file: path) }
        RobotLab.stub(:build, build) do
          run_orch(objective: "obj")
        end
        assert_equal 2, git_log_count, "a non-blocking decision must not stop the iteration from committing"
        mgr = decisions_for(latest_run_id)
        assert_equal 1, mgr.pending.size
        refute mgr.blocking_pending?
      end

      def test_handle_blocking_decisions_exit_mode_aborts_with_resume_hint
        with_tmp_dir do |dir|
          orch, mgr = orch_with_decisions(dir, decision_mode: "exit")
          mgr.record(question: "Q?", blocking: true, iteration: 1)
          err = assert_raises(AbortError) { orch.send(:handle_blocking_decisions) }
          assert_match(/awaiting human decision/, err.reason)
          assert_match(/--resume rid/, err.reason)
        end
      end

      def test_wait_mode_returns_once_decision_resolved
        with_tmp_dir do |dir|
          orch, mgr = orch_with_decisions(dir, decision_mode: "wait", decision_wait_poll: 1)
          d = mgr.record(question: "Q?", blocking: true, iteration: 1)
          resolver = Thread.new do
            sleep 0.2
            resolve_file(d)
          end
          orch.send(:handle_blocking_decisions)
          resolver.join
          refute mgr.blocking_pending?, "wait mode should return only after the block clears"
        end
      end

      def test_wait_mode_times_out
        with_tmp_dir do |dir|
          orch, mgr = orch_with_decisions(dir, decision_mode: "wait", decision_timeout: 0)
          mgr.record(question: "Q?", blocking: true, iteration: 1)
          orch.instance_variable_get(:@backoff).define_singleton_method(:sleep_seconds) { |_| }
          err = assert_raises(AbortError) { orch.send(:handle_blocking_decisions) }
          assert_match(/timed out/, err.reason)
        end
      end

      def test_exit_mode_pauses_then_resume_completes_the_run
        path   = File.join(@tmpdir, "feature.rb")
        build1 = ->(**kw) { DecisionRobot.new(kw[:local_tools][0], kw[:local_tools][1], blocking: true, write_file: path) }
        config1 = Config.new(decision_mode: "exit", max_iterations: 5)
        RobotLab.stub(:build, build1) do
          Dir.chdir(@tmpdir) { Orchestrator.new("obj", config1).run }
        end
        assert_equal 2, git_log_count, "the pre-pause iteration commits its safe work"

        run_id = latest_run_id
        mgr    = decisions_for(run_id)
        assert mgr.blocking_pending?, "exit mode leaves the blocking decision pending"
        mgr.blocking_pending.each { |d| resolve_file(d) }

        more   = File.join(@tmpdir, "more.rb")
        build2 = ->(**kw) { FakeRobot.new(kw[:local_tools][0], write_file: more) }
        config2 = Config.new(decision_mode: "exit", max_iterations: 2)
        RobotLab.stub(:build, build2) do
          Dir.chdir(@tmpdir) { Orchestrator.new(nil, config2, resume_run_id: run_id).run }
        end
        assert_equal 3, git_log_count, "resume continues on the same branch and commits again"
        # the resolved decision was consumed and closed
        assert_empty decisions_for(run_id).resolved_open
      end

      def test_resume_missing_state_aborts_cleanly
        Dir.chdir(@tmpdir) do
          Orchestrator.new(nil, Config.new, resume_run_id: "nope-0000").run
          # AbortError captured internally — no unhandled exception
        end
      end

      def test_run_state_json_written
        stub_build(FakeRobot) { run_orch }
        state = Dir.glob(File.join(@tmpdir, ".robot_lab_to", "runs", "**", "run.json"))
        refute_empty state
        data = JSON.parse(File.read(state.first))
        assert_equal "test objective", data["objective"]
      end
    end
  end
end
