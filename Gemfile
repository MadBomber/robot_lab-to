# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "flay"
gem "flog"
gem "irb"
gem "rake", "~> 13.0"
gem "rubocop"

gem "minitest", "~> 5.16"
gem "minitest-reporters"
gem "simplecov", require: false

gem "robot_lab", path: "../robot_lab"

# robot_lab's Network (used by examples/02_advanced_usage) requires ractor_queue
# via bus_poller.rb, but robot_lab does not declare it in its gemspec — so we add
# it here for the examples.
gem "ractor_queue"
