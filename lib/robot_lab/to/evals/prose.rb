# frozen_string_literal: true

module RobotLab
  module To
    module Evals
      # Judged / pairwise eval for prose products (docs, opinion, a book).
      #
      #   spec        - optional spec/outline artifact the judge measures against
      #   judge_model - model for the pairwise judge (defaults to the doer's model)
      #   floor       - optional command for mechanizable checks (links, coverage)
      #
      # The descent signal is a pairwise verdict: the judge is asked whether the
      # working tree is BETTER than the parent commit -- absolute scores from an
      # LLM are too noisy to descend. There is no measurable target, so met_target
      # is always false; runs end on --stop-on-plateau or a human.
      class Prose < Base
        JUDGE_SYSTEM = <<~PROMPT
          You are a meticulous editor. You will see two versions of a document
          (A = the previously accepted version, B = a new draft) plus the objective
          and, if given, the spec they serve. Decide whether B is BETTER, WORSE, or
          the SAME as A at satisfying them. Judge substance -- accuracy,
          completeness, clarity, structure -- not length. Reply with exactly one
          word: better, worse, or same.
        PROMPT

        def initialize(objective_model:, work_dir: Dir.pwd,
                       git: CommitManager.new(work_dir: work_dir),
                       judge_model: objective_model, spec: nil, floor: nil)
          super()
          @spec        = spec
          @judge_model = judge_model
          @floor       = floor
          @work_dir    = work_dir
          @git         = git
        end

        # The spec is the eval's own criteria and must be locked from the robot.
        def protected_paths = Array(@spec)

        def score(context)
          gate, output = floor_result
          verdict      = gate ? pairwise(context) : :worse
          Score.new(gate_ok: gate, improved: verdict == :better, met_target: false,
                    value: nil, detail: "floor=#{gate} judge=#{verdict}", output: output)
        end

        # Map a judge reply onto a verdict; defaults to :same when unclear so an
        # ambiguous judgment does not count as improvement.
        def parse_verdict(reply)
          text = reply.to_s.downcase
          return :better if text.match?(/\bbetter\b/)
          return :worse  if text.match?(/\bworse\b/)

          :same
        end

        private

        def floor_result
          return [true, nil] unless @floor

          result = Verifier.new(@floor, work_dir: @work_dir).run
          [result.passed?, result.output]
        end

        def pairwise(context)
          files = @git.changed_vs_worktree(context.previous_ref)
          return :same if files.empty?

          old = files.map { |f| @git.show(context.previous_ref, f) }.join("\n\n")
          new = files.map { |f| read_working(f) }.join("\n\n")
          # A brand-new document (no prior version) is an improvement over nothing.
          # Skip the judge: a pairwise "empty vs content" comparison is degenerate
          # and models frequently (wrongly) call it "same".
          return :better if old.strip.empty? && !new.strip.empty?

          parse_verdict(ask_judge(context.objective, old, new))
        end

        def ask_judge(objective, old, new)
          judge = RobotLab.build(name: "prose-judge", model: @judge_model, system_prompt: JUDGE_SYSTEM)
          # robot.run returns a RobotResult; its text is #last_text_content, NOT
          # #to_s (which is the object's inspection string).
          judge.run(comparison(objective, old, new)).last_text_content.to_s
        end

        def comparison(objective, old_text, new_text)
          spec_block = @spec && File.exist?(@spec) ? "SPEC:\n#{File.read(@spec)}\n\n" : ""
          <<~MSG
            OBJECTIVE: #{objective}

            #{spec_block}VERSION A (accepted):
            #{old_text}

            VERSION B (new draft):
            #{new_text}

            Is B better, worse, or the same as A? Reply with one word.
          MSG
        end

        def read_working(file)
          File.read(File.join(@work_dir, file))
        rescue SystemCallError
          ""
        end
      end
    end
  end
end
