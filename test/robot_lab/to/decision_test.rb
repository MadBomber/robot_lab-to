# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class DecisionTest < Minitest::Test
      def build(**overrides)
        defaults = {
          id: "d-20260701-120000-abc123", status: "pending", blocking: true,
          created_at: "2026-07-01T12:00:00Z", created_iteration: 3,
          resolved_at: nil, resolution: nil, question: "404 or 410?",
          situation: "public API", options: %w[404 410], recommendation: "410",
          body: "body", path: "/tmp/d.md"
        }
        Decision.new(**defaults, **overrides)
      end

      def test_status_predicates
        assert build(status: "pending").pending?
        assert build(status: "resolved").resolved?
        assert build(status: "closed").closed?
        assert build(status: "dismissed").dismissed?
        refute build(status: "pending").resolved?
      end

      def test_blocking_predicate_coerces
        assert build(blocking: true).blocking?
        refute build(blocking: false).blocking?
      end

      def test_answered_requires_resolved_and_resolution
        refute build(status: "resolved", resolution: nil).answered?
        refute build(status: "resolved", resolution: "  ").answered?
        refute build(status: "pending", resolution: "410").answered?
        assert build(status: "resolved", resolution: "410").answered?
      end
    end
  end
end
