require "rails_helper"

RSpec.describe Search::Resolver do
  let(:paris) { create(:destination, name: "Paris", country_code: "FR") }
  let(:barcelona) { create(:destination, name: "Barcelona", country_code: "ES") }
  let!(:tower) { create(:landmark, destination: paris, name: "Eiffel Tower", local_name: "Tour Eiffel", names: { "hu" => "Eiffel-torony" }) }
  let!(:rambla) { create(:landmark, destination: barcelona, name: "La Rambla", kind: "pedestrian_street") }
  let(:interpreter) { instance_double(Search::Interpreter, call: interpretation) }
  let(:interpretation) { nil }

  def resolve(text) = described_class.new(interpreter:).call(text)

  def interpreted(place: nil, anchors: [], kinds: [], max_minutes: nil, property_kinds: [])
    Search::Interpreter::Result.new(place:, anchors:, kinds:, max_minutes:, property_kinds:)
  end

  context "without a language model" do
    it "finds a landmark from the words in the text" do
      expect(resolve("hotel near the eiffel torony")).to have_attributes(status: :landmark, landmark: tower)
      expect(resolve("la rambla barcelona")).to have_attributes(status: :landmark, landmark: rambla)
    end

    it "goes to a destination named in the text, and says when nothing matches" do
      expect(resolve("something in Barcelona")).to have_attributes(status: :destination, destination: barcelona)
      expect(resolve("Atlantis")).to have_attributes(status: :none)
    end

    it "offers a choice when several places match about equally" do
      other = create(:landmark, destination: barcelona, name: "Eiffel Bridge")

      outcome = resolve("eiffel")
      expect(outcome.status).to eq(:choices)
      expect(outcome.landmarks).to contain_exactly(tower, other)
    end

    it "leaves out unpublished destinations" do
      paris.update!(published: false)

      expect(resolve("eiffel tower").status).to eq(:none)
    end
  end

  context "with a language model" do
    let(:interpretation) do
      interpreted(place: "Paris", anchors: [ { name: "Eiffel Tower", local_name: "Tour Eiffel", kind: "attraction" } ],
                  max_minutes: 10, property_kinds: [ "apartment" ])
    end

    it "uses the names it found and passes on the walk and kind of stay asked for" do
      expect(resolve("egy lakás 10 percre az eiffel toronytól")).to have_attributes(
        status: :landmark, landmark: tower, max_minutes: 10, property_kind: "apartment"
      )
    end

    context "when a kind of place is asked for" do
      let(:interpretation) { interpreted(place: "Barcelona", kinds: [ "pedestrian_street" ]) }

      it "lists stays near that kind of place in the destination" do
        expect(resolve("barcelona sétálóutca")).to have_attributes(status: :kind, destination: barcelona, kind: "pedestrian_street")
      end
    end

    context "when a kind of place is asked for without a destination" do
      let(:interpretation) { interpreted(kinds: [ "pedestrian_street" ]) }

      it "asks where" do
        expect(resolve("near a pedestrian street")).to have_attributes(status: :choose_destination, destinations: [ barcelona ])
      end
    end

    context "when the place is one we have not measured" do
      let(:interpretation) { interpreted(place: "Rome", anchors: [ { name: "Colosseum", local_name: "Colosseo", kind: nil } ]) }

      it "says so" do
        expect(resolve("colosseum")).to have_attributes(status: :none, place: "Rome")
      end
    end
  end
end
