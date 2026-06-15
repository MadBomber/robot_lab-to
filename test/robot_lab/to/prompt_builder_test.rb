# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class PromptBuilderTest < Minitest::Test
      def setup
        @config  = Config.new
        @builder = PromptBuilder.new(@config)
      end

      def test_includes_objective_and_iteration
        stub_run do |run, _dir|
          run.iteration = 3
          prompt = @builder.build(run, "")
          assert_includes prompt, run.objective
          assert_includes prompt, "iteration 3"
        end
      end

      def test_includes_notes_content
        stub_run do |run, _dir|
          prompt = @builder.build(run, "## Iteration Log\n\n### Iteration 1\ndid stuff")
          assert_includes prompt, "did stuff"
        end
      end

      def test_includes_no_iterations_yet_when_empty
        stub_run do |run, _dir|
          prompt = @builder.build(run, "")
          assert_includes prompt, "(no iterations yet)"
        end
      end

      def test_includes_repair_section_on_commit_failure
        stub_run do |run, _dir|
          err = CommitFailedError.new("conflict", output: "merge conflict on foo.rb")
          prompt = @builder.build(run, "", pending_commit_failure: err)
          assert_includes prompt, "Previous Commit Failure"
          assert_includes prompt, "merge conflict on foo.rb"
        end
      end

      def test_includes_stop_when_section_when_configured
        config = Config.new(stop_when: "all tests pass")
        builder = PromptBuilder.new(config)
        stub_run do |run, _dir|
          prompt = builder.build(run, "")
          assert_includes prompt, "all tests pass"
          assert_includes prompt, "should_fully_stop"
        end
      end

      def test_omits_stop_when_section_when_not_configured
        stub_run do |run, _dir|
          prompt = @builder.build(run, "")
          refute_includes prompt, "Stop Condition"
        end
      end

      def test_always_includes_submit_requirement
        stub_run do |run, _dir|
          prompt = @builder.build(run, "")
          assert_includes prompt, "submit_iteration_result"
        end
      end
    end
  end
end
