# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/test/"
  add_filter "/vendor/"
  add_group "To", "lib/robot_lab/to"
  enable_coverage :branch
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "robot_lab"
require "robot_lab/to"

require "minitest/autorun"
require "minitest/reporters"
require "tmpdir"
require "pathname"

# rubocop:disable Style/FileOpen, Style/GlobalStdStream, Layout/LineLength
$stdout = File.open("test_output.txt", "w").tap { |f| f.sync = true }

class TerminalSummaryReporter < Minitest::Reporters::BaseReporter
  def report
    super
    ok    = failures.zero? && errors.zero?
    badge = ok ? "\e[32mPASS\e[0m" : "\e[31mFAIL\e[0m"
    STDOUT.puts "[#{badge}] #{count} tests, #{failures} failures, #{errors} errors, " \
                "#{skips} skips (#{format("%.2f", total_time)}s) — see test_output.txt"
    STDOUT.flush
  end
end
# rubocop:enable Style/FileOpen, Style/GlobalStdStream, Layout/LineLength

Minitest::Reporters.use! [
  Minitest::Reporters::DefaultReporter.new(color: false, slow_count: 5),
  TerminalSummaryReporter.new
]

module RobotLab
  module To
    module TestHelpers
      def with_tmp_dir
        Dir.mktmpdir do |dir|
          yield Pathname.new(dir)
        end
      end

      def stub_run(objective: "test objective", run_id: "20260615-120000-abc123",
                   branch: "robot-to/test-20260615-120000")
        with_tmp_dir do |dir|
          notes_path = dir.join("notes.md")
          log_path   = dir.join("run.log")
          run = Run.new(run_id: run_id, objective: objective, branch: branch,
                        base_commit: "abc1234", notes_path: notes_path, log_path: log_path)
          yield run, dir
        end
      end
    end
  end
end

include RobotLab::To::TestHelpers
