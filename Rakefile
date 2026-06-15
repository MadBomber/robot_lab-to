# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb", "test/**/test_*.rb"].exclude("**/*_helper.rb")
  t.verbose = true
  t.ruby_opts << "-rtest_helper"
end

task default: :test

desc "Run tests with verbose output"
task :test_verbose do
  ENV["TESTOPTS"] = "--verbose"
  Rake::Task[:test].invoke
end

desc "Run a single test file"
task :test_file, [:file] do |_t, args|
  ruby "test/#{args[:file]}"
end

desc "Check code complexity with Flog (warn >=20, fail >=50)"
task :flog_check do
  require "flog"

  method_warn = 20.0
  method_fail = 50.0

  flogger = Flog.new(all: true)
  flogger.flog(*Dir.glob("lib/**/*.rb"))

  warnings = []
  failures = []

  flogger.each_by_score do |method, score|
    next if method.end_with?("#none")

    if score > method_fail
      failures << "#{format("%.1f", score)}: #{method}"
    elsif score > method_warn
      warnings << "#{format("%.1f", score)}: #{method}"
    end
  end

  unless warnings.empty?
    puts "\nFlog warnings (#{method_warn}–#{method_fail}) — target for future refactoring:"
    warnings.each { |v| puts "  #{v}" }
  end

  if failures.empty?
    puts "\nFlog: no methods exceed the failure threshold (>=#{method_fail})"
  else
    puts "\nFlog failures (>=#{method_fail}) — must be refactored:"
    failures.each { |v| puts "  #{v}" }
    abort "\nFlog quality gate failed: #{failures.size} method(s) exceed #{method_fail}"
  end
end

desc "Run all quality checks: tests (with coverage), RuboCop, Flog"
task :quality do
  results = {}

  puts "\n#{"=" * 60}"
  puts "Quality Gate: Tests + Coverage"
  puts "=" * 60
  results[:tests] = system("bundle exec rake test") ? :pass : :fail

  puts "\n#{"=" * 60}"
  puts "Quality Gate: RuboCop"
  puts "=" * 60
  results[:rubocop] = system("bundle exec rubocop") ? :pass : :fail

  puts "\n#{"=" * 60}"
  puts "Quality Gate: Flog Complexity"
  puts "=" * 60
  results[:flog] = system("bundle exec rake flog_check") ? :pass : :fail

  puts "\n#{"=" * 60}"
  puts "Quality Summary"
  puts "=" * 60
  results.each do |gate, status|
    icon = status == :pass ? "PASS" : "FAIL"
    puts "  [#{icon}] #{gate}"
  end
  puts "=" * 60

  abort "\nQuality gate failed" if results.values.any?(:fail)
  puts "\nAll quality gates passed."
end
