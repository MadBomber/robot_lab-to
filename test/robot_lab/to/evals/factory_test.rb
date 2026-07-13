# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Evals
      class FactoryTest < Minitest::Test
        # A minimal eval used to prove instance/registry pass-through.
        class StubEval < Base
          def score(_ctx) = :stub_score
        end

        def teardown
          RobotLab::To.evals.delete(:factory_test_dummy)
        end

        def test_default_with_no_verify_is_null
          assert_instance_of Null, Evals.build(Config.new)
        end

        def test_default_with_verify_command_is_code
          assert_instance_of Code, Evals.build(Config.new(verify_command: "true"))
        end

        def test_named_code
          assert_instance_of Code, Evals.build(Config.new(eval: "code"))
        end

        def test_named_null
          assert_instance_of Null, Evals.build(Config.new(eval: "null"))
        end

        def test_named_prose
          assert_instance_of Prose, Evals.build(Config.new(eval: "prose"))
        end

        def test_measure_alone_selects_code_not_null
          assert_instance_of Code, Evals.build(Config.new(eval_measure: "rake cov"))
        end

        def test_instance_passed_through_unchanged
          stub = StubEval.new
          assert_same stub, Evals.build(Config.new(eval: stub))
        end

        def test_proc_is_wrapped_and_delegates
          built = Evals.build(Config.new(eval: ->(_ctx) { :from_proc }))
          assert_instance_of ProcEval, built
          assert_equal :from_proc, built.score(nil)
        end

        def test_registered_symbol_is_resolved
          RobotLab::To.register_eval(:factory_test_dummy) { |_config| StubEval.new }
          assert_instance_of StubEval, Evals.build(Config.new(eval: :factory_test_dummy))
        end

        def test_unregistered_symbol_raises
          error = assert_raises(ArgumentError) { Evals.build(Config.new(eval: :nope_not_registered)) }
          assert_match(/no eval registered/, error.message)
        end

        def test_unknown_strategy_raises
          error = assert_raises(ArgumentError) { Evals.build(Config.new(eval: "banana")) }
          assert_match(/unknown eval strategy/, error.message)
        end
      end
    end
  end
end
