# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class NotesManagerTest < Minitest::Test
      def test_setup_creates_file_with_header
        stub_run do |run, dir|
          nm = NotesManager.new(dir.join("notes.md"))
          nm.setup(run)
          content = nm.read
          assert_includes content, "# robot-to run: #{run.run_id}"
          assert_includes content, "Objective: #{run.objective}"
          assert_includes content, "## Iteration Log"
        end
      end

      def test_append_success_writes_entry
        stub_run do |run, dir|
          nm = NotesManager.new(dir.join("notes.md"))
          nm.setup(run)
          result = IterationResult.new(success: true, summary: "added auth",
                                       key_changes: ["lib/auth.rb"], key_learnings: ["use bcrypt"],
                                       should_fully_stop: nil)
          nm.append_success(result, 1)
          content = nm.read
          assert_includes content, "### Iteration 1"
          assert_includes content, "added auth"
          assert_includes content, "lib/auth.rb"
          assert_includes content, "use bcrypt"
        end
      end

      def test_append_failure_marks_fail
        stub_run do |run, dir|
          nm = NotesManager.new(dir.join("notes.md"))
          nm.setup(run)
          result = IterationResult.new(success: false, summary: "tests broken",
                                       key_changes: [], key_learnings: ["skip flaky test"],
                                       should_fully_stop: nil)
          nm.append_failure(result, 2)
          content = nm.read
          assert_includes content, "### Iteration 2 [FAIL]"
          assert_includes content, "tests broken"
        end
      end

      def test_append_verify_failure_records_output
        stub_run do |run, dir|
          nm = NotesManager.new(dir.join("notes.md"))
          nm.setup(run)
          result = IterationResult.new(success: true, summary: "added feature",
                                       key_changes: [], key_learnings: [], should_fully_stop: nil)
          nm.append_verify_failure(result, "3 runs, 1 failure", 4)
          content = nm.read
          assert_includes content, "### Iteration 4 [VERIFY FAILED]"
          assert_includes content, "3 runs, 1 failure"
        end
      end

      def test_append_error_marks_error
        stub_run do |run, dir|
          nm = NotesManager.new(dir.join("notes.md"))
          nm.setup(run)
          nm.append_error(RuntimeError.new("boom"), 3)
          assert_includes nm.read, "### Iteration 3 [ERROR]"
          assert_includes nm.read, "RuntimeError: boom"
        end
      end

      def test_read_returns_empty_string_when_missing
        with_tmp_dir do |dir|
          nm = NotesManager.new(dir.join("missing.md"))
          assert_equal "", nm.read
        end
      end

      def test_append_decision_records_question_and_recommendation
        stub_run do |run, dir|
          nm = NotesManager.new(dir.join("notes.md"))
          nm.setup(run)
          decision = Decision.new(id: "d-1", status: "pending", blocking: true,
                                  created_at: "2026-07-01T12:00:00Z", created_iteration: 2,
                                  resolved_at: nil, resolution: nil, question: "404 or 410?",
                                  situation: "", options: [], recommendation: "410 Gone",
                                  body: "", path: "/tmp/d-1.md")
          nm.append_decision(decision, 2)
          content = nm.read
          assert_includes content, "### Iteration 2 [DECISION]"
          assert_includes content, "404 or 410?"
          assert_includes content, "**Blocking:** yes"
          assert_includes content, "410 Gone"
          assert_includes content, "/tmp/d-1.md"
        end
      end
    end
  end
end
