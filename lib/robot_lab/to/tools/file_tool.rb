# frozen_string_literal: true

module RobotLab
  module To
    module Tools
      # Base for robot_lab-to's built-in workspace tools. RubyLLM derives a
      # fully-namespaced tool name (e.g. "robot_lab--to--tools--read"); small
      # models do far better with the short, conventional names the guards and
      # skill docs reference, so we expose the bare last segment ("read",
      # "write", "edit", "bash", ...).
      class FileTool < RobotLab::Tool
        # @return [String] the short, lowercase tool name
        def name
          self.class.short_name
        end

        # @return [String] last class path segment, snake_cased
        def self.short_name
          name_segment ||
            to_s.split("::").last
                .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                .downcase
        end

        # Subclasses may override the derived short name.
        # @return [String, nil]
        def self.name_segment = nil
      end
    end
  end
end
