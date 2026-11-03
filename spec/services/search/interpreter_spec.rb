require "rails_helper"

RSpec.describe Search::Interpreter do
  let(:endpoint) { "https://llm.example/v1/chat/completions" }
  let(:interpreter) { described_class.new(api_key: "test-key", base_url: "https://llm.example/v1", model: "test-model", cache: ActiveSupport::Cache::NullStore.new) }

  def reply(content, status: 200)
    stub_request(:post, endpoint).to_return(status:, body: { choices: [ { message: { content: } } ] }.to_json)
  end

  it "sends only the typed text and reads the structured answer" do
    reply(<<~JSON)
      Here you go: {"place": "Paris", "anchors": [{"name": "Eiffel Tower", "local_name": "Tour Eiffel", "kind": "attraction"}],
       "kinds": ["beach", "volcano"], "max_walk_minutes": 45, "property_kinds": ["hotel", "castle"]}
    JSON

    result = interpreter.call("  eiffel   torony ")

    expect(result).to have_attributes(place: "Paris", kinds: [ "beach" ], max_minutes: 30, property_kinds: [ "hotel" ])
    expect(result.anchor_names).to eq([ "Eiffel Tower", "Tour Eiffel" ])
    expect(WebMock).to have_requested(:post, endpoint).with { |request|
      body = JSON.parse(request.body)
      request.headers["Authorization"] == "Bearer test-key" && body["model"] == "test-model" &&
        body["messages"].last == { "role" => "user", "content" => "eiffel torony" }
    }
  end

  it "returns nil when the model fails or answers nonsense" do
    reply("", status: 500)
    expect(interpreter.call("eiffel")).to be_nil

    reply("I cannot help with that.")
    expect(interpreter.call("eiffel")).to be_nil

    stub_request(:post, endpoint).to_timeout
    expect(interpreter.call("eiffel")).to be_nil
  end

  it "does nothing without an API key" do
    expect(described_class.new(api_key: nil).call("eiffel")).to be_nil
    expect(WebMock).not_to have_requested(:any, //)
  end
end
