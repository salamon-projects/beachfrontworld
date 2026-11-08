namespace :websites do
  desc "Check the websites of listed properties now and report the broken ones"
  task check: :environment do
    CheckWebsitesJob.perform_now
    broken = Property.published.with_broken_website
    puts "#{Property.published.with_website.count} websites checked, #{broken.count} broken"
    broken.find_each { |property| puts "  #{property.name}: #{property.website} (#{property.website_status})" }
  end
end
