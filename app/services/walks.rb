module Walks
  # How long the admin's walking limit is remembered by each process.
  MAX_WALK_TTL = 30.seconds

  def self.config
    @config ||= Rails.application.config_for(:walks)
  end

  # The longest walk that counts as near (SiteSetting#max_walk_m).
  def self.max_walk_m
    if @max_walk_m.nil? || @max_walk_m_read_at < MAX_WALK_TTL.ago
      @max_walk_m = SiteSetting.current.max_walk_m
      @max_walk_m_read_at = Time.current
    end
    @max_walk_m
  end

  def self.reset_max_walk_m!
    @max_walk_m = nil
  end

  # The walking settings with the current limit, for Walks::Measurement.
  def self.measurement_config
    config.merge(max_walk_m:)
  end

  # Whole minutes at an easy pace, at least one.
  def self.minutes(metres)
    [ (metres / config.fetch(:metres_per_minute).to_f).round, 1 ].max
  end

  # Steps, rounded to tens: a measurement, not a pedometer.
  def self.steps(metres)
    (metres / config.fetch(:metres_per_step).to_f).round(-1)
  end
end
