module LandmarksHelper
  # How often the page waiting for a measurement updates itself.
  REFRESH_SECONDS = 4

  # How far measuring has come: looking for stays, stays found, walks
  # measured so far.
  def measuring_status(landmark, measured, pending)
    if measured.positive?
      t("landmarks.measuring.measured_so_far", count: measured)
    elsif pending.positive?
      t("landmarks.measuring.stays_found", count: pending)
    else
      t("landmarks.measuring.title", name: landmark.name)
    end
  end
end
