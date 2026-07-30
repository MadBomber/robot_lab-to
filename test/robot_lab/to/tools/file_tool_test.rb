# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Tools
      class FileToolTest < Minitest::Test
        def test_tools_expose_short_lowercase_names
          assert_equal "read", Read.new.name
          assert_equal "write", Write.new.name
          assert_equal "edit", Edit.new.name
          assert_equal "bash", Bash.new.name
        end

        def test_short_name_is_derived_from_class
          assert_equal "read", Read.short_name
        end
      end
    end
  end
end
