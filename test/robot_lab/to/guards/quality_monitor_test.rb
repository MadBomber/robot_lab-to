# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Guards
      class QualityMonitorTest < Minitest::Test
        QM = QualityMonitor

        def setup
          Thread.current[QM::KEY] = nil
        end

        # ---- pure assess --------------------------------------------------------

        def test_assess_flags_empty_response
          assert_equal :empty_response, QM.assess("", [], [], [])
        end

        def test_assess_ok_with_text
          assert_equal :ok, QM.assess("hello", [], [], [])
        end

        def test_assess_ok_with_tool_call
          assert_equal :ok, QM.assess("", [{ name: "read", input: {} }], [], [])
        end

        def test_assess_flags_empty_tool_name
          assert_equal :empty_tool_name, QM.assess("", [{ name: "", input: {} }], [], [])
        end

        def test_assess_flags_unknown_tool_when_registry_known
          assert_equal "unknown_tool:Frob", QM.assess("", [{ name: "Frob", input: {} }], [], ["read"])
        end

        def test_assess_allows_unknown_tool_when_registry_empty
          assert_equal :ok, QM.assess("", [{ name: "Frob", input: {} }], [], [])
        end

        # ---- repeated? ----------------------------------------------------------

        def test_repeated_detects_identical_call
          prev = [{ name: "read", input: { path: "a" } }]
          assert QM.repeated?([{ name: "read", input: { path: "a" } }], prev)
        end

        def test_repeated_false_for_different_args
          prev = [{ name: "read", input: { path: "a" } }]
          refute QM.repeated?([{ name: "read", input: { path: "b" } }], prev)
        end

        def test_repeated_false_without_history
          refute QM.repeated?([{ name: "read", input: {} }], [])
        end

        # ---- after_tool_call loop escalation -----------------------------------

        def test_repeated_calls_raise_after_budget
          dispatch(QM, :before_run, run_ctx)
          args = { "path" => "a" }
          # First call: records. Next two: repeats (1,2). Third repeat (3) > MAX(2) raises.
          dispatch(QM, :after_tool_call, tool_ctx("read", args))
          dispatch(QM, :after_tool_call, tool_ctx("read", args))
          dispatch(QM, :after_tool_call, tool_ctx("read", args))
          assert_raises(QM::QualityError) do
            dispatch(QM, :after_tool_call, tool_ctx("read", args))
          end
        end

        def test_different_calls_reset_repeat_counter
          dispatch(QM, :before_run, run_ctx)
          dispatch(QM, :after_tool_call, tool_ctx("read", { "path" => "a" }))
          dispatch(QM, :after_tool_call, tool_ctx("read", { "path" => "a" }))
          dispatch(QM, :after_tool_call, tool_ctx("read", { "path" => "b" })) # resets
          # Two more identical 'b' calls should not raise (counter reset).
          dispatch(QM, :after_tool_call, tool_ctx("read", { "path" => "b" }))
          dispatch(QM, :after_tool_call, tool_ctx("read", { "path" => "b" }))
        end

        def test_correction_message_for_known_reasons
          assert_includes QM.correction_message("repeated_tool_call"), "stuck"
          assert_includes QM.correction_message("empty_response"), "empty"
          assert_includes QM.correction_message("unknown_tool:Frob"), "Frob"
        end

        def test_quality_error_carries_reason
          err = QM::QualityError.new(:repeated_tool_call)
          assert_equal :repeated_tool_call, err.reason
        end
      end
    end
  end
end
