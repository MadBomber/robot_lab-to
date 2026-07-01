# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class PromptBuilderTest < Minitest::Test
      def setup
        @config  = Config.new
        @builder = PromptBuilder.new(@config)
      end

      def test_includes_verify_section_naming_the_command
        config  = Config.new(verify_command: "bundle exec rake test")
        builder = PromptBuilder.new(config)
        stub_run do |run, _dir|
          prompt = builder.build(run, "")
          assert_includes prompt, "Verification"
          assert_includes prompt, "bundle exec rake test"
          assert_includes prompt, "make it pass BEFORE"
        end
      end

      def test_omits_verify_section_without_command
        stub_run do |run, _dir|
          refute_includes @builder.build(run, ""), "## Verification"
        end
      end

      def test_includes_workspace_section_when_files_given
        stub_run do |run, _dir|
          prompt = @builder.build(run, "", workspace: ["test/a_test.rb", "lib/a.rb"])
          assert_includes prompt, "## Project Files"
          assert_includes prompt, "- test/a_test.rb"
          assert_includes prompt, "- lib/a.rb"
        end
      end

      def test_omits_workspace_section_when_empty
        stub_run do |run, _dir|
          refute_includes @builder.build(run, "", workspace: []), "## Project Files"
        end
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

      def resolved_decision(question: "404 or 410?", resolution: "410 Gone")
        Decision.new(id: "d-1", status: "resolved", blocking: true,
                     created_at: "2026-07-01T12:00:00Z", created_iteration: 1,
                     resolved_at: "2026-07-01T13:00:00Z", resolution: resolution,
                     question: question, situation: "", options: [], recommendation: "",
                     body: "", path: "/tmp/d-1.md")
      end

      def test_includes_decision_guidance_when_enabled
        stub_run do |run, _dir|
          prompt = @builder.build(run, "")
          assert_includes prompt, "When to Ask for a Human Decision"
          assert_includes prompt, "request_decision"
        end
      end

      def test_omits_decision_guidance_when_disabled
        config  = Config.new(decisions_enabled: false)
        builder = PromptBuilder.new(config)
        stub_run do |run, _dir|
          refute_includes builder.build(run, ""), "When to Ask for a Human Decision"
        end
      end

      def test_injects_answered_decisions
        stub_run do |run, _dir|
          prompt = @builder.build(run, "", resolved_decisions: [resolved_decision])
          assert_includes prompt, "Answered Decisions"
          assert_includes prompt, "404 or 410?"
          assert_includes prompt, "410 Gone"
        end
      end

      def test_omits_answered_section_when_none
        stub_run do |run, _dir|
          refute_includes @builder.build(run, "", resolved_decisions: []), "Answered Decisions"
        end
      end
    end
  end
end
