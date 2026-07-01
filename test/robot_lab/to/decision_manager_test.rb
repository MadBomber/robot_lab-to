# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    class DecisionManagerTest < Minitest::Test
      def with_manager
        with_tmp_dir do |dir|
          mgr = DecisionManager.new(dir.join("decisions"))
          mgr.setup
          yield mgr, dir
        end
      end

      # Flip a decision file on disk the way a human would.
      def resolve(decision, answer: "Option 2")
        raw = File.read(decision.path)
        raw = raw.sub("status: pending", "status: resolved")
                 .sub("resolution:", "resolution: #{answer}")
                 .sub("resolved_at:", "resolved_at: 2026-07-01T13:00:00Z")
        File.write(decision.path, raw)
      end

      def test_record_writes_parseable_file
        with_manager do |mgr|
          d = mgr.record(question: "404 or 410?", situation: "public API",
                         options: %w[404 410], recommendation: "410", blocking: true, iteration: 5)
          assert File.exist?(d.path)
          assert_equal "404 or 410?", d.question
          assert d.pending?
          assert d.blocking?
          assert_equal 5, d.created_iteration
          assert_match(/\Ad-\d{8}-\d{6}-[0-9a-f]{6}\z/, d.id)
        end
      end

      def test_record_persists_situation_options_recommendation_in_body
        with_manager do |mgr|
          d = mgr.record(question: "Q?", situation: "the stakes", options: %w[A B],
                         recommendation: "A because reasons", iteration: 1)
          body = File.read(d.path)
          assert_includes body, "the stakes"
          assert_includes body, "1. A"
          assert_includes body, "2. B"
          assert_includes body, "A because reasons"
        end
      end

      def test_all_sorted_and_classified
        with_manager do |mgr|
          d1 = mgr.record(question: "one", iteration: 1)
          _d2 = mgr.record(question: "two", blocking: true, iteration: 2)
          assert_equal 2, mgr.all.size
          assert_equal 2, mgr.pending.size
          assert_empty mgr.resolved_open
          assert mgr.blocking_pending?
          assert_equal 1, mgr.blocking_pending.size

          resolve(d1)
          assert_equal 1, mgr.pending.size
          assert_equal 1, mgr.resolved_open.size
        end
      end

      def test_reload_picks_up_external_resolution
        with_manager do |mgr|
          d = mgr.record(question: "Q?", blocking: true, iteration: 1)
          refute d.answered?
          resolve(d, answer: "go with B")
          reloaded = mgr.reload(d)
          assert reloaded.resolved?
          assert reloaded.answered?
          assert_equal "go with B", reloaded.resolution
        end
      end

      def test_blocking_pending_excludes_resolved
        with_manager do |mgr|
          d = mgr.record(question: "Q?", blocking: true, iteration: 1)
          assert mgr.blocking_pending?
          resolve(d)
          refute mgr.blocking_pending?
        end
      end

      def test_close_flips_status_and_preserves_resolution
        with_manager do |mgr|
          d = mgr.record(question: "Q?", blocking: true, iteration: 1)
          resolve(d, answer: "keep this answer")
          resolved = mgr.reload(d)
          mgr.close(resolved)
          closed = mgr.reload(d)
          assert closed.closed?
          assert_equal "keep this answer", closed.resolution
          assert_empty mgr.resolved_open
        end
      end

      def test_resolution_falls_back_to_body_section
        with_manager do |mgr|
          d = mgr.record(question: "Q?", iteration: 1)
          raw = File.read(d.path)
          # Human answers in the body instead of the front matter.
          raw = raw.sub("status: pending", "status: resolved")
                   .sub("## Your Decision\n", "## Your Decision\nUse the second option.\n")
          File.write(d.path, raw)
          reloaded = mgr.reload(d)
          assert_equal "Use the second option.", reloaded.resolution
        end
      end

      def test_lenient_parse_survives_malformed_front_matter
        with_manager do |dir_mgr, dir|
          path = dir.join("decisions", "d-20260701-120000-deadbe.md")
          File.write(path, <<~MD)
            ---
            id: d-20260701-120000-deadbe
            status: pending
            blocking: true
            resolution: contains: an unquoted colon that breaks YAML
            ---
            # Decision: broken but recoverable
          MD
          d = dir_mgr.all.find { |x| x.id == "d-20260701-120000-deadbe" }
          refute_nil d
          assert d.pending?
          assert d.blocking?
        end
      end
    end
  end
end
