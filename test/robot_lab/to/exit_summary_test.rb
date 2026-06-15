# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class ExitSummaryTest < Minitest::Test
      def test_prints_complete_on_clean_exit
        stub_run do |run, _dir|
          run.iteration      = 5
          run.commits        = 4
          run.input_tokens   = 10_000
          run.output_tokens  = 2_000
          config = Config.new(model: "claude-sonnet-4")
          summary = ExitSummary.new(run, config)
          out = capture_io { summary.print }.first
          assert_includes out, "robot-to complete"
          assert_includes out, "claude-sonnet-4"
          assert_includes out, "5 total"
        end
      end

      def test_prints_stopped_on_abort
        stub_run do |run, _dir|
          config = Config.new
          summary = ExitSummary.new(run, config, abort_reason: "max iterations reached (3)")
          out = capture_io { summary.print }.first
          assert_includes out, "robot-to stopped"
          assert_includes out, "max iterations reached"
        end
      end

      def test_prints_token_counts_with_commas
        stub_run do |run, _dir|
          run.input_tokens  = 1_234_567
          run.output_tokens = 89_012
          config = Config.new
          out = capture_io { ExitSummary.new(run, config).print }.first
          assert_includes out, "1,234,567"
        end
      end

      def test_omits_next_steps_when_no_commits
        stub_run do |run, _dir|
          run.commits = 0
          config = Config.new
          out = capture_io { ExitSummary.new(run, config).print }.first
          refute_includes out, "git log"
        end
      end

      def test_shows_next_steps_when_commits_exist
        stub_run do |run, _dir|
          run.commits = 2
          config = Config.new
          out = capture_io { ExitSummary.new(run, config).print }.first
          assert_includes out, "git log"
          assert_includes out, "gh pr create"
        end
      end
    end
  end
end
