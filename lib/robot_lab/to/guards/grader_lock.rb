# frozen_string_literal: true

require_relative "path_resolution"

module RobotLab
  module To
    module Guards
      # Refuses any attempt by the robot to modify its own grader artifacts (the
      # eval's spec / floor script / --protect-path files), so it cannot "win" by
      # rewriting the criteria it is scored against.
      #
      # Unlike the other guards, this one is installed unconditionally whenever
      # protected paths exist -- not gated behind --local-guards -- because a
      # frontier model can reward-hack too. The protected absolute paths are
      # passed in via context: { paths: [...] }.
      class GraderLock < RobotLab::Hook
        self.namespace = :grader_lock

        MUTATING_TOOLS = %w[write edit].freeze
        BASH_TOOLS     = %w[bash].freeze

        class << self
          def around_tool_call(ctx)
            paths = Array(ctx.local.paths)
            return yield if paths.empty?

            target = offending_path(ctx, paths)
            return yield unless target

            ctx.tool_result = refusal(target)
          end

          # The locked path a tool call targets, or nil if it touches none.
          # Write/Edit are matched by resolved path; Bash by the command string
          # referencing an absolute path or a locked basename (conservative).
          def offending_path(ctx, paths)
            name = ctx.tool_name.to_s.downcase
            if MUTATING_TOOLS.include?(name)
              resolved = PathResolution.resolve(ctx.tool_args)
              resolved if resolved && paths.include?(resolved)
            elsif BASH_TOOLS.include?(name)
              command_hits(ctx.tool_args, paths)
            end
          end

          def command_hits(args, paths)
            command = (args["command"] || args[:command]).to_s
            paths.find { |p| command.include?(p) || command.include?(File.basename(p)) }
          end

          def refusal(path)
            <<~MSG
              Refused -- #{path} is a locked grader artifact (the criteria you are
              scored against). You must not create, edit, or delete it. Improve the
              work being scored instead.
            MSG
          end
        end
      end
    end
  end
end
