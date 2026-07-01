# frozen_string_literal: true

require "securerandom"
require "yaml"

module RobotLab
  module To
    # Reads and writes decision files under <run_dir>/decisions/.
    #
    # Parallels NotesManager: the orchestrator records decisions the robot
    # raises and queries their status each iteration; a human resolves them by
    # editing the file between iterations (or between cron ticks).
    #
    # Each decision is a markdown file with a YAML front matter block:
    #
    #   ---
    #   id: d-20260701-143022-a1b2c3
    #   status: pending
    #   blocking: true
    #   created_at: 2026-07-01T14:30:22Z
    #   created_iteration: 7
    #   resolved_at:
    #   resolution:
    #   ---
    #   # Decision: <question>
    #   ...
    #
    # All writes go through AtomicFile so a crash never leaves a torn file.
    class DecisionManager
      GLOB = "d-*.md"

      attr_reader :dir

      def initialize(dir)
        @dir = Pathname.new(dir)
      end

      def setup
        @dir.mkpath
      end

      # Persist a decision the robot raised. Returns the parsed Decision.
      def record(question:, situation: "", options: [], recommendation: "", blocking: false, iteration: 0)
        id   = generate_id
        path = @dir.join("#{id}.md")
        AtomicFile.write(path, render_new(id: id, question: question, situation: situation,
                                          options: Array(options), recommendation: recommendation.to_s,
                                          blocking: blocking ? true : false, iteration: iteration.to_i))
        parse(path)
      end

      # All decisions on disk, oldest first (ids sort chronologically).
      def all
        Dir.glob(@dir.join(GLOB)).map { |p| parse(p) }.compact
      end

      def pending       = all.select(&:pending?)
      # resolved but not yet closed
      def resolved_open = all.select(&:resolved?)
      def blocking_pending = all.select { |d| d.pending? && d.blocking? }
      def blocking_pending? = blocking_pending.any?

      # Re-read a single decision from disk (a human may have edited it).
      def reload(decision) = parse(decision.path)

      # Mark a resolved decision closed: its resolution has been delivered to a
      # robot and committed, so it should no longer be re-injected. Flips only
      # the status line, preserving whatever the human wrote in the body.
      def close(decision)
        raw = File.read(decision.path)
        AtomicFile.write(decision.path, flip_status(raw, "closed"))
      end

      private

      def generate_id
        "d-#{Time.now.strftime("%Y%m%d-%H%M%S")}-#{SecureRandom.hex(3)}"
      end

      # Replace the status: line inside the leading front matter block only.
      def flip_status(raw, status)
        raw.sub(/^status:.*$/, "status: #{status}")
      end

      def render_new(id:, question:, situation:, options:, recommendation:, blocking:, iteration:)
        options_md = options.empty? ? "(none provided)\n" : options.each_with_index.map { |o, i| "#{i + 1}. #{o}" }.join("\n") + "\n"
        # Build the front matter with YAML.dump so question/recommendation are
        # escaped correctly (they can contain colons, quotes, etc.).
        front = {
          "id" => id, "status" => "pending", "blocking" => blocking,
          "created_at" => Time.now.utc.iso8601, "created_iteration" => iteration,
          "resolved_at" => nil, "resolution" => nil,
          "question" => question, "recommendation" => recommendation
        }
        fm = YAML.dump(front).sub(/\A---\n/, "").chomp
        <<~MD
          ---
          #{fm}
          ---
          # Decision: #{question}

          ## Situation
          #{situation.to_s.strip.empty? ? "(none provided)" : situation.strip}

          ## Options
          #{options_md}
          ## Recommendation (robot's lean)
          #{recommendation.strip.empty? ? "(none provided)" : recommendation.strip}

          ## Your Decision
          <!-- Human: set `status: resolved` and fill `resolution:` in the front
               matter above (or write your answer below this line), then re-run
               robot-to (or `robot-to --resume <run_id>`). -->
        MD
      end

      # Split a file into (front_matter_hash, body). Returns a Decision or nil
      # when the file is unreadable.
      def parse(path)
        text = File.read(path)
        fm, body = split_front_matter(text)
        Decision.new(
          id:                fm["id"] || File.basename(path, ".md"),
          status:            (fm["status"] || "pending").to_s,
          blocking:          truthy?(fm["blocking"]),
          created_at:        fm["created_at"].to_s,
          created_iteration: fm["created_iteration"].to_i,
          resolved_at:       presence(fm["resolved_at"]),
          resolution:        resolution_for(fm, body),
          question:          fm["question"].to_s,
          situation:         fm["situation"].to_s,
          options:           Array(fm["options"]),
          recommendation:    fm["recommendation"].to_s,
          body:              body,
          path:              path.to_s
        )
      rescue SystemCallError
        nil
      end

      def split_front_matter(text)
        if text.start_with?("---\n") && (close_idx = text.index("\n---", 4))
          raw_fm = text[4...close_idx]
          body   = text[(close_idx + 4)..].to_s.sub(/\A\n/, "")
          [safe_yaml(raw_fm), body]
        else
          [{}, text]
        end
      end

      # YAML.safe_load, falling back to a lenient line scanner when a human's
      # hand-edited front matter is not valid YAML.
      def safe_yaml(raw)
        parsed = YAML.safe_load(raw, permitted_classes: [Date, Time])
        parsed.is_a?(Hash) ? stringify(parsed) : lenient_parse(raw)
      rescue Psych::Exception
        lenient_parse(raw)
      end

      def lenient_parse(raw)
        raw.lines.each_with_object({}) do |line, h|
          next unless (m = line.match(/^([a-z_]+):\s*(.*)$/))

          h[m[1]] = m[2].strip
        end
      end

      def stringify(hash)
        hash.transform_keys(&:to_s).transform_values { |v| v.is_a?(Time) ? v.utc.iso8601 : v }
      end

      # Prefer the front matter resolution; fall back to prose under
      # "## Your Decision" (stripping the HTML instruction comment).
      def resolution_for(fm, body)
        fm_res = presence(fm["resolution"])
        return fm_res if fm_res

        section = body[/^##\s+Your Decision\s*\n(.*)\z/m, 1].to_s
        section = section.gsub(/<!--.*?-->/m, "").strip
        presence(section)
      end

      def presence(value)
        s = value.to_s.strip
        s.empty? ? nil : s
      end

      def truthy?(value)
        %w[true yes 1].include?(value.to_s.strip.downcase)
      end
    end
  end
end
