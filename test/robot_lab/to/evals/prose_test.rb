# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Evals
      class ProseTest < Minitest::Test
        # Stand-in for CommitManager: canned changed files + old contents.
        class FakeGit
          def initialize(changed: [], contents: {})
            @changed  = changed
            @contents = contents
          end

          def changed_vs_worktree(_ref) = @changed
          def show(_ref, path) = @contents.fetch(path, "")
        end

        def setup
          @tmpdir = Dir.mktmpdir
        end

        def teardown
          FileUtils.rm_rf(@tmpdir)
        end

        def test_pairwise_better_verdict_is_improvement
          score = with_judge("better") { build_prose(changed: ["a.md"]).score(context) }
          assert score.gate_ok?
          assert score.improved?
          refute score.met_target?, "prose never sets a measurable target"
          assert_nil score.value
        end

        def test_pairwise_worse_verdict_is_not_improvement
          score = with_judge("worse") { build_prose(changed: ["a.md"]).score(context) }
          refute score.improved?
        end

        def test_no_changed_files_is_not_improvement
          # empty diff short-circuits to :same without invoking the judge
          score = build_prose(changed: []).score(context)
          refute score.improved?
        end

        def test_new_document_is_improvement_without_calling_judge
          # A brand-new file (no prior version) beats nothing: commit it without a
          # degenerate empty-vs-content judge call.
          File.write(File.join(@tmpdir, "a.md"), "a real first draft")
          boom = ->(**) { raise "judge must not be called for a brand-new document" }
          score = RobotLab.stub(:build, boom) { build_prose(changed: ["a.md"]).score(context) }
          assert score.improved?, "a brand-new document is an improvement over nothing"
        end

        def test_floor_failure_closes_gate_and_skips_judge
          score = build_prose(changed: ["a.md"], floor: "exit 1").score(context)
          refute score.gate_ok?
          refute score.improved?
        end

        def test_floor_pass_allows_the_judge
          score = with_judge("better") { build_prose(changed: ["a.md"], floor: "true").score(context) }
          assert score.gate_ok?
          assert score.improved?
        end

        def test_parse_verdict_maps_words
          prose = build_prose
          assert_equal :better, prose.parse_verdict("Version B is BETTER")
          assert_equal :worse,  prose.parse_verdict("worse than A")
          assert_equal :same,   prose.parse_verdict("about the same")
          assert_equal :same,   prose.parse_verdict("no clear signal")
        end

        def test_protected_paths_locks_the_spec
          assert_equal ["/x/outline.md"], build_prose(spec: "/x/outline.md").protected_paths
          assert_empty build_prose(spec: nil).protected_paths
        end

        def test_judge_model_defaults_to_objective_model
          captured = nil
          capture = lambda do |**kw|
            captured = kw[:model]
            fake_judge("better")
          end
          RobotLab.stub(:build, capture) do
            build_prose(changed: ["a.md"]).score(context)
          end
          assert_equal "doer-model", captured
        end

        private

        def context
          Context.new(work_dir: @tmpdir, previous_ref: "HEAD", previous_value: nil,
                      objective: "write a guide", iteration: 1)
        end

        def build_prose(changed: [], floor: nil, spec: nil)
          Prose.new(objective_model: "doer-model", spec: spec, floor: floor,
                    work_dir: @tmpdir, git: FakeGit.new(changed: changed))
        end

        def fake_judge(reply)
          # robot.run returns a RobotResult whose text is #last_text_content.
          result = Object.new
          result.define_singleton_method(:last_text_content) { reply }
          judge = Object.new
          judge.define_singleton_method(:run) { |_msg| result }
          judge
        end

        def with_judge(reply, &)
          RobotLab.stub(:build, ->(**) { fake_judge(reply) }, &)
        end
      end
    end
  end
end
