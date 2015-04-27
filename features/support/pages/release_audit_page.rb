require 'uri'

module Pages
  class ReleaseAuditPage


    def initialize(page:, url_helpers:)
      @page        = page
      @url_helpers = url_helpers
    end

    def request(from:, to:)
      page.visit url_helpers.release_audits_path
      page.fill_in :from, with: from
      page.fill_in :to, with: to
      page.click_link_or_button('Submit')
      self
    end

    def authors
      page.all('.author').map(&:text)
    end

  private

    attr_reader :page, :url_helpers
  end
end