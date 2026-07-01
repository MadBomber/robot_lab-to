# frozen_string_literal: true

module RobotLab
  module To
    # An immutable snapshot of one decision file on disk.
    #
    # A decision is the artifact the robot writes when it hits a choice it
    # should not make autonomously: the situation, the options, and its own
    # recommended "lean". A human resolves it out-of-band by editing the file
    # (set `status: resolved`, fill `resolution:`); a later iteration reads the
    # resolution back in.
    #
    # Status lifecycle: pending -> resolved (by human) -> closed (resolution
    # delivered to a robot and committed). `dismissed` is a terminal human veto.
    Decision = Data.define(
      :id,                # String  — d-YYYYMMDD-HHMMSS-<hex>
      :status,            # String  — pending | resolved | closed | dismissed
      :blocking,          # Boolean — does the loop pause until this is resolved?
      :created_at,        # String  — ISO8601
      :created_iteration, # Integer
      :resolved_at,       # String or nil — ISO8601
      :resolution,        # String or nil — the human's answer (best available)
      :question,          # String
      :situation,         # String
      :options,           # Array<String>
      :recommendation,    # String
      :body,              # String  — full markdown body (below front matter)
      :path               # String  — absolute path to the file
    ) do
      def pending?   = status.to_s == "pending"
      def resolved?  = status.to_s == "resolved"
      def closed?    = status.to_s == "closed"
      def dismissed? = status.to_s == "dismissed"
      def blocking?  = !!blocking

      # True when a human has answered (resolved with a non-empty resolution).
      def answered? = resolved? && !resolution.to_s.strip.empty?
    end
  end
end
