#--
# Copyright (c) 2005 Robert Aman
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'feed_tools'
require 'uri'

module FeedTools
  # Generic url processing methods needed in numerous places throughout
  # FeedTools
  module UriHelper
    # Attempts to ensures that the passed url is valid and sane.  Accepts very,
    # very ugly urls and makes every effort to figure out what it was supposed
    # to be.  Also translates from the feed: and rss: pseudo-protocols to the
    # http: protocol.
    def self.normalize_url(url)
      if url.kind_of?(URI)
        url = url.to_s
      end
      if url.blank?
        return nil
      end
      normalized_url = CGI.unescape(url.strip)

      # if a url begins with the '/' character, it only makes sense that they
      # meant to be using a file:// url.  Fix it for them.
      if normalized_url.length > 0 && normalized_url[0..0] == "/"
        normalized_url = "file://" + normalized_url
      end

      # if a url begins with a drive letter followed by a colon, we're looking at
      # a file:// url.  Fix it for them.
      if normalized_url.length > 0 &&
          normalized_url.scan(/^[a-zA-Z]:[\\\/]/).size > 0
        normalized_url = "file:///" + normalized_url
      end

      # if a url begins with javascript:, it's quite possibly an attempt at
      # doing something malicious.  Let's keep that from getting anywhere,
      # shall we?
      if (normalized_url.downcase =~ /javascript:/) != nil
        return "#"
      end

      # deal with all of the many ugly possibilities involved in the rss:
      # and feed: pseudo-protocols (incidentally, whose crazy idea was this
      # mess?)
      normalized_url.gsub!(/^http:\/*(feed:\/*)?/i, "http://")
      normalized_url.gsub!(/^http:\/*(rss:\/*)?/i, "http://")
      normalized_url.gsub!(/^feed:\/*(http:\/*)?/i, "http://")
      normalized_url.gsub!(/^rss:\/*(http:\/*)?/i, "http://")
      normalized_url.gsub!(/^file:\/*/i, "file:///")
      normalized_url.gsub!(/^https:\/*/i, "https://")
      # fix (very) bad urls (usually of the user-entered sort)
      normalized_url.gsub!(/^http:\/*(http:\/*)*/i, "http://")

      if (normalized_url =~ /^file:/i) == 0
        # Adjust windows-style urls
        normalized_url.gsub!(/^file:\/\/\/([a-zA-Z])\|/i, 'file:///\1:')
        normalized_url.gsub!(/\\/, '/')
      else
        if (normalized_url =~ /https?:\/\//i) == nil
          normalized_url = "http://" + normalized_url
        end
        if normalized_url == "http://"
          return nil
        end
        begin
          feed_uri = URI.parse(normalized_url)
          if feed_uri.scheme == nil
            feed_uri.scheme = "http"
          end
          if feed_uri.path.blank?
            feed_uri.path = "/"
          end
          if (feed_uri.path =~ /^[\/]+/) == 0
            feed_uri.path.gsub!(/^[\/]+/, "/")
          end
          while (feed_uri.path =~ /^\/\.\./)
            feed_uri.path.gsub!(/^\/\.\./, "")
          end
          if feed_uri.path.blank?
            feed_uri.path = "/"
          end
          feed_uri.host.downcase!
          normalized_url = feed_uri.to_s
        rescue URI::InvalidURIError
        end
      end

      # We can't do a proper set of escaping, so this will
      # have to do.
      normalized_url.gsub!(/%20/, " ")
      normalized_url.gsub!(/ /, "%20")

      return normalized_url
    end

    # Converts a url into a tag uri
    def self.build_tag_uri(url, date)
      unless url.kind_of? String
        raise ArgumentError, "Expected String, got #{url.class.name}"
      end
      unless date.kind_of? Time
        raise ArgumentError, "Expected Time, got #{date.class.name}"
      end
      tag_uri = normalize_url(url)
      unless FeedTools::UriHelper.is_uri?(tag_uri)
        raise ArgumentError, "Must supply a valid URL."
      end
      host = URI.parse(tag_uri).host
      tag_uri.gsub!(/^(http|ftp|file):\/*/, "")
      tag_uri.gsub!(/#/, "/")
      tag_uri = "tag:#{host},#{date.strftime('%Y-%m-%d')}:" +
        "#{tag_uri[(tag_uri.index(host) + host.size)..-1]}"
      return tag_uri
    end

    # Converts a url into a urn:uuid: uri
    def self.build_urn_uri(url)
      unless url.kind_of? String
        raise ArgumentError, "Expected String, got #{url.class.name}"
      end
      normalized_url = normalize_url(url)
      require 'uuidtools'
      return UUID.sha1_create(UUID_URL_NAMESPACE, normalized_url).to_uri_string
    end

    # Returns true if the parameter appears to be a valid uri
    def self.is_uri?(url)
      return false if url.nil?
      begin
        uri = URI.parse(url)
        if uri.scheme.blank?
          return false
        end
      rescue URI::InvalidURIError
        return false
      end
      return true
    end
  end
end