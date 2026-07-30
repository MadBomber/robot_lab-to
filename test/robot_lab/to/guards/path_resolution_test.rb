# frozen_string_literal: true

require "test_helper"

module RobotLab
  module To
    module Guards
      class PathResolutionTest < Minitest::Test
        def test_normalize_rewrites_root_bare_path_to_cwd
          assert_equal "/work/foo.md", PathResolution.normalize("/foo.md", cwd: "/work")
        end

        def test_normalize_resolves_relative_against_cwd
          assert_equal "/work/a/b.rb", PathResolution.normalize("a/b.rb", cwd: "/work")
        end

        def test_normalize_leaves_real_absolute_path_untouched
          assert_equal "/etc/hosts", PathResolution.normalize("/etc/hosts", cwd: "/work")
        end

        def test_raw_path_reads_path_key
          assert_equal "x.rb", PathResolution.raw_path("path" => "x.rb")
        end

        def test_raw_path_reads_file_path_key
          assert_equal "y.rb", PathResolution.raw_path("file_path" => "y.rb")
        end

        def test_raw_path_accepts_symbol_keys
          assert_equal "z.rb", PathResolution.raw_path(path: "z.rb")
        end

        def test_raw_path_returns_nil_without_path
          assert_nil PathResolution.raw_path("content" => "x")
        end

        def test_resolve_combines_extraction_and_normalization
          assert_equal "/w/a.rb", PathResolution.resolve({ "path" => "a.rb" }, cwd: "/w")
        end

        def test_resolve_returns_nil_without_path
          assert_nil PathResolution.resolve({ "content" => "x" }, cwd: "/w")
        end
      end
    end
  end
end
