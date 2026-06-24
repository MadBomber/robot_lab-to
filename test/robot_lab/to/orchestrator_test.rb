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

        def run(_objective)
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
        def run(_objective) = nil
      end

      # Silent on the first run; submits (with a file change) only when nudged.
      class NudgeThenSubmitRobot
        def initialize(tool, write_file:)
          @tool       = tool
          @write_file = write_file
          @calls      = 0
        end

        def run(_task)
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

        def run(_objective)
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

        def run(_task)
          @calls += 1
          File.write(@write_file, @calls >= 2 ? "good" : "bad")
          @tool.execute(success: true, summary: "attempt #{@calls}",
                        key_changes: [@write_file], key_learnings: [])
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

        def run(_objective)
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
    end
  end
end
