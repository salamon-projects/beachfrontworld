namespace :walks do
  desc "Measure walks from every property to the landmarks of a destination (by slug), or all destinations"
  task :measure, [ :slug ] => :environment do |_, args|
    scope = args[:slug] ? Destination.where(slug: args[:slug]) : Destination.all
    scope.find_each do |destination|
      stored = Walks::Measurement.new(destination.landmarks).call
      puts "#{destination.name}: #{stored} walks to #{destination.landmarks.count} landmarks"
    end
  end
end
