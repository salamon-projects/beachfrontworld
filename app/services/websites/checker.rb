require "net/http"
require "resolv"
require "ipaddr"

module Websites
  # Checks that a property's website (from OSM or an admin) still loads, so the
  # site never sends visitors to a dead or empty page. A clear failure (no such
  # domain, 404, empty or parked page) hides the link at once; a failure that
  # may pass (timeout, server error) hides it only when the next check fails
  # too. Sites that refuse automated visitors (401, 403, 429) keep their link:
  # that says nothing about whether people can open them.
  #
  # Only public addresses are fetched: the host is resolved first and the
  # connection goes to that address, so a URL cannot reach our own network.
  class Checker
    Result = Data.define(:outcome, :status) do
      def ok? = outcome == :ok
    end

    USER_AGENT = "Mozilla/5.0 (compatible; StepsFrom link check; +https://stepsfrom.com)".freeze
    MAX_REDIRECTS = 5
    BLOCKED_STATUSES = [ 401, 403, 405, 406, 429, 999 ].freeze
    GONE_STATUSES = [ 404, 410 ].freeze
    # A page that is only whitespace, or a few bytes of markup, shows nothing.
    MIN_BODY_BYTES = 64
    PARKED = /domain\s+(is|may\s+be)\s+for\s+sale|buy\s+this\s+domain|this\s+domain\s+(is\s+)?parked|parked\s+free|sedoparking|hugedomains\.com/i
    TRANSIENT_ERRORS = [ Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
                         Errno::ENETUNREACH, OpenSSL::SSL::SSLError, EOFError, IOError, SocketError,
                         Net::HTTPBadResponse, Zlib::Error ].freeze

    def initialize(resolver: Resolv, open_timeout: 8, read_timeout: 12)
      @resolver = resolver
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    # Checks the property's website and records the result on it.
    def record(property)
      result = check(property.website)
      property.update_columns(**attributes_for(property, result), updated_at: Time.current)
      result
    end

    def check(url)
      uri = parse(url) or return Result.new(:broken, "not a web address")
      MAX_REDIRECTS.times do
        response = fetch(uri)
        return response if response.is_a?(Result)

        location = response["location"] if response.is_a?(Net::HTTPRedirection)
        return classify(response) unless location

        uri = parse(URI.join(uri, location).to_s) or return Result.new(:broken, "redirects to a non-web address")
      end
      Result.new(:failing, "too many redirects")
    rescue *TRANSIENT_ERRORS => e
      Result.new(:failing, "no response (#{e.class.name.demodulize})")
    end

    private

    def attributes_for(property, result)
      failures = result.outcome.in?(%i[ok unknown]) ? 0 : property.website_failures + 1
      broken = result.outcome == :broken || (result.outcome == :failing && failures >= 2)
      { website_checked_at: Time.current, website_status: result.status, website_failures: failures,
        website_broken_at: (broken ? property.website_broken_at || Time.current : nil) }
    end

    def parse(url)
      uri = URI.parse(url.to_s.strip)
      uri if uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      nil
    end

    # The response, or a Result when the host cannot or must not be reached.
    def fetch(uri)
      addresses = @resolver.getaddresses(uri.host)
      return Result.new(:broken, "domain not found") if addresses.empty?

      address = addresses.find { |a| public_address?(a) } or return Result.new(:broken, "not a public address")
      http = Net::HTTP.new(uri.host, uri.port)
      http.ipaddr = address
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      request["Accept"] = "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8"
      http.request(request)
    end

    def public_address?(address)
      ip = IPAddr.new(address)
      !(ip.private? || ip.loopback? || ip.link_local? || ip.to_i.zero? ||
        IPAddr.new("100.64.0.0/10").include?(ip) || IPAddr.new("fc00::/7").include?(ip))
    rescue IPAddr::InvalidAddressError
      false
    end

    def classify(response)
      code = response.code.to_i
      return Result.new(:unknown, "HTTP #{code} (refuses automated checks)") if BLOCKED_STATUSES.include?(code)
      return Result.new(:broken, "HTTP #{code}") if GONE_STATUSES.include?(code)
      return Result.new(:failing, "HTTP #{code}") unless response.is_a?(Net::HTTPSuccess)

      body = response.body.to_s
      return Result.new(:broken, "empty page") if body.strip.bytesize < MIN_BODY_BYTES
      return Result.new(:broken, "parked domain") if body.scrub.match?(PARKED)

      Result.new(:ok, "HTTP #{code}")
    end
  end
end
