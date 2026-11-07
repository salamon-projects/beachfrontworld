class PagesController < ApplicationController
  def how_we_verify
    @config = Waterfront.config
  end

  def affiliate_disclosure; end

  def privacy; end

  def robots
    render plain: <<~TXT
      User-agent: *
      Disallow: /go/
      Disallow: /admin
      Disallow: /search

      Sitemap: #{sitemap_url}
    TXT
  end
end
