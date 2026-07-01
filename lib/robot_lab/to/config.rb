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
      attr_writer :provider, :model, :max_iterations, :max_tokens, :stop_when,
                  :max_consecutive_failures, :max_submit_nudges, :max_verify_repairs,
                  :verify_command, :verify_timeout, :run_dir, :commit_format,
                  :local_guards, :stream, :debug,
                  :decisions_enabled, :decision_mode, :decision_wait_poll, :decision_timeout

      def initialize(**overrides)
        super()
        overrides.each { |k, v| public_send(:"#{k}=", v) if respond_to?(:"#{k}=") }
      end

      # Keys defined in defaults.yml — super is safe
      def provider                 = @provider || super
      def model                    = @model || super
      def max_consecutive_failures = @max_consecutive_failures || super
      def max_submit_nudges        = @max_submit_nudges        || super
      def max_verify_repairs       = @max_verify_repairs       || super
      def verify_timeout           = @verify_timeout           || super

      def run_dir                  = @run_dir          || super
      def commit_format            = @commit_format    || super
      def local_guards?            = @local_guards.nil? ? super : @local_guards
      def stream?                  = @stream.nil? ? super : @stream
      def debug?                   = @debug.nil? ? super : @debug

      def decisions_enabled?       = @decisions_enabled.nil? ? super : @decisions_enabled
      def decision_mode            = @decision_mode      || super
      def decision_wait_poll       = @decision_wait_poll || super
      # nil = wait indefinitely
      def decision_timeout         = @decision_timeout   || super

      # CLI-only options with no YAML default (nil means "no limit / not set")
      def max_iterations           = @max_iterations
      def max_tokens               = @max_tokens
      def stop_when                = @stop_when
      def verify_command           = @verify_command
    end
  end
end
