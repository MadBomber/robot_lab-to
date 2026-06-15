# frozen_string_literal: true

require_relative "lib/robot_lab/to/version"

Gem::Specification.new do |spec|
  spec.name = "robot_lab-to"
  spec.version = RobotLab::To::VERSION
  spec.authors = ["Dewayne VanHoozer"]
  spec.email = ["dvanhoozer@gmail.com"]

  spec.summary = "Autonomous overnight agent loop for RobotLab — run robots while you sleep."
  spec.description = <<~DESC
    robot_lab-to ("takeover") runs a robot_lab Robot in an autonomous loop, committing
    one focused change per iteration toward a stated objective. Each iteration the robot
    reads shared notes (notes.md), does work, then calls submit_iteration_result to
    report success or failure. The orchestrator commits good iterations, rolls back
    failures, and appends to the notes log for cross-iteration memory. Stop conditions
    include max iterations, max tokens, consecutive failure threshold, and a natural-
    language --stop-when condition. Runs overnight; review the branch in the morning.
  DESC
  spec.homepage = "https://github.com/MadBomber/robot_lab-to"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) || f.start_with?(*%w[bin/ Gemfile .gitignore test/])
    end
  end

  spec.bindir = "bin"
  spec.executables = ["robot-to"]
  spec.require_paths = ["lib"]

  spec.add_dependency "robot_lab", ">= 0.1"
  spec.add_dependency "myway_config"
end
