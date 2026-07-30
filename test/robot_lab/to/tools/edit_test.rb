# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Tools
      class EditTest < Minitest::Test
        # ---- pure apply ---------------------------------------------------------

        def test_apply_replaces_unique_match
          assert_equal "a X c", Edit.new.apply("a b c", "b", "X", false)
        end

        def test_apply_errors_when_not_found
          assert_includes Edit.new.apply("abc", "z", "X", false), "not found"
        end

        def test_apply_errors_on_ambiguous_match
          assert_includes Edit.new.apply("b b", "b", "X", false), "not unique"
        end

        def test_apply_replace_all
          assert_equal "X X", Edit.new.apply("b b", "b", "X", true)
        end

        # ---- execute ------------------------------------------------------------

        def test_execute_edits_file
          with_tmp_dir do |dir|
            path = dir.join("f.rb").to_s
            File.write(path, "value = 1\n")
            Edit.new.execute(path: path, old_text: "1", new_text: "2")
            assert_equal "value = 2\n", File.read(path)
          end
        end

        def test_execute_missing_file
          assert_includes Edit.new.execute(path: "/no/file", old_text: "a", new_text: "b"),
                          "Error: file not found"
        end

        def test_execute_leaves_file_unchanged_on_ambiguous_match
          with_tmp_dir do |dir|
            path = dir.join("f.rb").to_s
            File.write(path, "x x")
            Edit.new.execute(path: path, old_text: "x", new_text: "y")
            assert_equal "x x", File.read(path)
          end
        end
      end
    end
  end
end
