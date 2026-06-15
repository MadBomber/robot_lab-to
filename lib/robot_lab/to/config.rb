# frozen_string_literal: true

require "myway_config"

module RobotLab
  module To
    # Configuration for a robot-to run.
    #
    # Sources (lowest to highest precedence):
    #   1. Bundled defaults (config/defaults.yml)
    #   2. User config file (~/.config/robot_lab/to.yml)
    #   3. Environment variables (ROBOT_LAB_TO_*)
    #   4. Constructor keyword arguments (CLI overrides)
    class Config < MywayConfig::Base
      config_name :robot_lab_to
      env_prefix :robot_lab_to
      defaults_path File.expand_path("config/defaults.yml", __dir__)
      auto_configure!

      # Runtime CLI overrides — applied after load.
      attr_writer :model, :max_iterations, :max_tokens, :stop_when,
                  :max_consecutive_failures, :run_dir, :commit_format, :debug

      def initialize(**overrides)
        super()
        overrides.each { |k, v| public_send(:"#{k}=", v) if respond_to?(:"#{k}=") }
      end

      # Keys defined in defaults.yml — super is safe
      def model                    = @model || super
      def max_consecutive_failures = @max_consecutive_failures || super

      def run_dir                  = @run_dir          || super
      def commit_format            = @commit_format    || super
      def debug?                   = @debug.nil? ? super : @debug

      # CLI-only options with no YAML default (nil means "no limit / not set")
      def max_iterations           = @max_iterations
      def max_tokens               = @max_tokens
      def stop_when                = @stop_when
    end
  end
end
