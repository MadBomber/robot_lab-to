# frozen_string_literal: true

module RobotLab
  module To
    module Tools
      # Exact-string replacement in an existing file. old_text must match the
      # file's current contents exactly (whitespace included) and be unique
      # unless replace_all is set. The ReadBeforeEdit guard requires the file to
      # have been Read this session first, so old_text reflects real contents.
      class Edit < FileTool
        description <<~DESC
          Replace an exact substring in an existing file. old_text must match the
          current file contents exactly (including whitespace) and be unique unless
          replace_all is true. Read the file first to get the exact text.
        DESC

        param :path, type: "string", desc: "Path of the file to edit"
        param :old_text, type: "string", desc: "Exact text to replace"
        param :new_text, type: "string", desc: "Replacement text"
        param :replace_all, type: "boolean", desc: "Replace every occurrence", required: false

        # :reek:BooleanParameter -- replace_all is a tool param the LLM sets;
        # the `param` declarations above fix this signature.
        # :reek:FeatureEnvy -- inspecting #apply's own return value.
        # :reek:TooManyStatements -- validate, transform, write, report; each
        # step is one statement in a tool #execute contract method.
        def execute(path:, old_text:, new_text:, replace_all: false, **)
          resolved = File.expand_path(path, Dir.pwd)
          return "Error: file not found: #{path}" unless File.file?(resolved)

          original = File.read(resolved)
          result = apply(original, old_text.to_s, new_text.to_s, replace_all)
          return result if result.is_a?(String) && result.start_with?("Error:")

          File.write(resolved, result)
          "Edited #{path}"
        rescue SystemCallError => e
          "Error editing #{path}: #{e.message}"
        end

        # Pure replacement logic (testable in isolation). Returns the new content
        # string, or an "Error: ..." string on a precondition failure.
        #
        # @return [String]
        def apply(content, old_text, new_text, replace_all)
          count = content.scan(old_text).size
          return "Error: old_text not found in file" if count.zero?
          if count > 1 && !replace_all
            return "Error: old_text is not unique (#{count} matches); add context or set replace_all"
          end

          replace_all ? content.gsub(old_text, new_text) : content.sub(old_text, new_text)
        end
      end
    end
  end
end
