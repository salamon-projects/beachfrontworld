module Walks
  def self.config
    @config ||= Rails.application.config_for(:walks)
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
