require "rails_helper"

RSpec.describe CheckWebsitesJob do
  it "checks the websites of listed properties only" do
    listed = create(:property, :direct, website: "https://listed.example/")
    create(:property, website: "https://unlisted.example/")
    create(:property, :direct)
    checker = instance_double(Websites::Checker)
    allow(Websites::Checker).to receive(:new).and_return(checker)
    allow(checker).to receive(:record)

    described_class.perform_now

    expect(checker).to have_received(:record).once.with(listed)
  end
end
