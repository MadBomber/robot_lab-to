# frozen_string_literal: true

module RobotLab
  module To
    module Evals
      # Wraps a bare callable (proc/lambda) as an Eval.
      class ProcEval < Base
        def initialize(callable)
          super()
          @callable = callable
        end

        def score(context)
          @callable.call(context)
        end
      end

      # Resolves the configured eval strategy into an object responding to
      # #score(context). Precedence: an explicit instance (responds to #score) or
      # proc, a registered symbol, then the named built-ins, then a default that
      # matches legacy behavior (Code when a verify command is set, else Null).
      #
      # Phase 1 ships "code" and "null"; "prose", file paths, and "auto" arrive in
      # later phases (they raise a clear error until then).
      def self.build(config, git: nil)
        chosen = config.respond_to?(:eval) ? config.eval : nil
        return chosen if chosen.respond_to?(:score)
        return ProcEval.new(chosen) if chosen.is_a?(Proc)

        from_name(chosen, config)
      end

      def self.from_name(chosen, config)
        case chosen
        when Symbol then from_registry(chosen, config)
        when "code" then code(config)
        when "null" then Null.new
        when nil    then use_code?(config) ? code(config) : Null.new
        else raise ArgumentError, unknown_strategy(chosen)
        end
      end

      # Default to Code when any of its inputs are configured (a verify command,
      # a measure command, or a target); otherwise Null preserves legacy behavior.
      def self.use_code?(config)
        !blank?(config.verify_command) || !config.eval_measure.nil? || !config.eval_target.nil?
      end

      def self.code(config)
        Code.new(verify:  presence(config.verify_command),
                 measure: presence(config.eval_measure),
                 target:  config.eval_target,
                 timeout: config.verify_timeout)
      end

      def self.from_registry(name, config)
        block = RobotLab::To.evals[name]
        raise ArgumentError, "no eval registered as #{name.inspect}" unless block

        block.call(config)
      end

      def self.presence(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      def self.blank?(value) = presence(value).nil?

      def self.unknown_strategy(chosen)
        "unknown eval strategy: #{chosen.inspect} (available: code, null, " \
          "a symbol registered via RobotLab::To.register_eval, " \
          "an object responding to #score, or a proc)"
      end
    end
  end
end
