# frozen_string_literal: true

module RobotLab
  module To
    # Manages the cross-iteration notes file (notes.md).
    #
    # Written by the orchestrator only. The robot reads it at the start of every
    # iteration to understand prior work.
    class NotesManager
      attr_reader :path

      def initialize(path)
        @path = Pathname.new(path)
      end

      def setup(run)
        AtomicFile.write(@path, <<~HEADER)
          # robot-to run: #{run.run_id}

          Objective: #{run.objective}

          ## Iteration Log
        HEADER
      end

      def read
        @path.exist? ? @path.read : ""
      end

      def append_success(result, iteration)
        changes_md = bullet_list(result.key_changes)
        learnings_md = bullet_list(result.key_learnings)
        append(<<~MD)

          ### Iteration #{iteration}

          **Summary:** #{result.summary}

          **Changes:**
          #{changes_md}
          **Learnings:**
          #{learnings_md}
        MD
      end

      def append_failure(result, iteration)
        learnings_md = bullet_list(result.key_learnings)
        append(<<~MD)

          ### Iteration #{iteration} [FAIL]

          **Summary:** #{result.summary}

          **Learnings:**
          #{learnings_md}
        MD
      end

      def append_verify_failure(result, output, iteration)
        append(<<~MD)

          ### Iteration #{iteration} [VERIFY FAILED]

          **Summary:** #{result.summary}

          **Verification output:**
          ```
          #{output}
          ```
        MD
      end

      def append_error(error, iteration)
        append(<<~MD)

          ### Iteration #{iteration} [ERROR]

          **Error:** #{error.class}: #{error.message}
        MD
      end

      def append_decision(decision, iteration)
        append(<<~MD)

          ### Iteration #{iteration} [DECISION]

          **Raised:** #{decision.question}
          **Blocking:** #{decision.blocking? ? "yes" : "no"}
          **Recommendation:** #{decision.recommendation}
          **File:** #{decision.path}
        MD
      end

      private

      def append(text)
        AtomicFile.append(@path, text)
      end

      def bullet_list(items)
        return "- (none)\n" if items.nil? || items.empty?

        items.map { |i| "- #{i}" }.join("\n") + "\n"
      end
    end
  end
end
