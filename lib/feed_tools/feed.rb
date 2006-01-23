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

require 'feed_tools/helpers/generic_helper'

module FeedTools
  # The <tt>FeedTools::Feed</tt> class represents a web feed's structure.
  class Feed
    # :stopdoc:
    include REXML
    class << self
      include FeedTools::GenericHelper
      private :validate_options
    end
    include FeedTools::GenericHelper
    private :validate_options
    # :startdoc:
  
    # Represents a feed/feed item's category
    class Category
    
      # The category term value
      attr_accessor :term
      # The categorization scheme
      attr_accessor :scheme
      # A human-readable description of the category
      attr_accessor :label
    
      alias_method :value, :term
      alias_method :category, :term
      alias_method :domain, :scheme
    end
  
    # Represents a feed/feed item's author
    class Author

      # The author's real name
      attr_accessor :name
      # The author's email address
      attr_accessor :email
      # The url of the author's homepage
      attr_accessor :url
      # The raw value of the author tag if present
      attr_accessor :raw
    end
  
    # Represents a feed's image
    class Image

      # The image's title
      attr_accessor :title
      # The image's description
      attr_accessor :description
      # The image's url
      attr_accessor :url
      # The url to link the image to
      attr_accessor :link
      # The width of the image
      attr_accessor :width
      # The height of the image
      attr_accessor :height
      # The style of the image
      # Possible values are "icon", "image", or "image-wide"
      attr_accessor :style
    end

    # Represents a feed's text input element.
    # Be aware that this will be ignored for feed generation.  It's a
    # pointless element that aggregators usually ignore and it doesn't have an
    # equivalent in all feeds types.
    class TextInput

      # The label of the Submit button in the text input area.
      attr_accessor :title
      # The description explains the text input area.
      attr_accessor :description
      # The URL of the CGI script that processes text input requests.
      attr_accessor :link
      # The name of the text object in the text input area.
      attr_accessor :name
    end
  
    # Represents a feed's cloud.
    # Be aware that this will be ignored for feed generation.
    class Cloud

      # The domain of the cloud.
      attr_accessor :domain
      # The path for the cloud.
      attr_accessor :path
      # The port the cloud is listening on.
      attr_accessor :port
      # The web services protocol the cloud uses.
      # Possible values are either "xml-rpc" or "soap".
      attr_accessor :protocol
      # The procedure to use to request notification.
      attr_accessor :register_procedure
    end
  
    # Represents a simple hyperlink
    class Link

      # The url that is being linked to
      attr_accessor :url
      # The content of the hyperlink
      attr_accessor :value
    
      alias_method :href, :url
    end
  
    # Initialize the feed object
    def initialize
      super
      @cache_object = nil
      @http_headers = nil
      @xml_doc = nil
      @feed_data = nil
      @feed_data_type = :xml
      @root_node = nil
      @channel_node = nil
      @url = nil
      @id = nil
      @title = nil
      @description = nil
      @link = nil
      @last_retrieved = nil
      @time_to_live = nil
      @entries = nil
      @live = false
    end
          
    # Loads the feed specified by the url, pulling the data from the
    # cache if it hasn't expired.
    # Options are:
    # * <tt>:cache_only</tt> - If set to true, the feed will only be
    #   pulled from the cache.
    def Feed.open(url, options={})
      validate_options([ :cache_only ],
                       options.keys)
      options = { :cache_only => false }.merge(options)
      
      if options[:cache_only] && FeedTools.feed_cache.nil?
        raise(ArgumentError, "There is currently no caching mechanism set. " +
          "Cannot retrieve cached feeds.")
      end
      
      # clean up the url
      url = FeedTools.normalize_url(url)

      # create and load the new feed
      feed = FeedTools::Feed.new
      feed.url = url
      feed.update! unless options[:cache_only]
      return feed
    end

    # Loads the feed from the remote url if the feed has expired from the cache or cannot be
    # retrieved from the cache for some reason.
    def update!
      if !FeedTools.feed_cache.nil? &&
          !FeedTools.feed_cache.set_up_correctly?
        raise "Your feed cache system is incorrectly set up.  " +
          "Please see the documentation for more information."
      end
      if self.http_headers.blank? && !(self.cache_object.nil?) &&
          !(self.cache_object.http_headers.nil?)
        @http_headers = YAML.load(self.cache_object.http_headers)
        @http_headers = {} unless @http_headers.kind_of? Hash
      elsif self.http_headers.blank?
        @http_headers = {}
      end
      if self.expired? == false
        @live = false
      else
        load_remote_feed!
      end
    end
  
    # Attempts to load the feed from the remote location.  Requires the url
    # field to be set.  If an etag or the last_modified date has been set,
    # attempts to use them to prevent unnecessary reloading of identical
    # content.
    def load_remote_feed!
      @live = true
      if self.http_headers.nil? && !(self.cache_object.nil?) &&
          !(self.cache_object.http_headers.nil?)
        @http_headers = YAML.load(self.cache_object.http_headers)
      end
    
      if (self.url =~ /^feed:/) == 0
        # Woah, Nelly, how'd that happen?  You should've already been
        # corrected.  So let's fix that url.  And please,
        # just use less crappy browsers instead of badly defined
        # pseudo-protocol hacks.
        self.url = FeedTools.normalize_url(self.url)
      end
    
      # Find out what method we're going to be using to obtain this feed.
      begin
        uri = URI.parse(self.url)
      rescue URI::InvalidURIError
        raise FeedAccessError,
          "Cannot retrieve feed using invalid URL: " + self.url.to_s
      end
      retrieval_method = "http"
      case uri.scheme
      when "http"
        retrieval_method = "http"
      when "ftp"
        retrieval_method = "ftp"
      when "file"
        retrieval_method = "file"
      when nil
        raise FeedAccessError,
          "No protocol was specified in the url."
      else
        raise FeedAccessError,
          "Cannot retrieve feed using unrecognized protocol: " + uri.scheme
      end
    
      # No need for http headers unless we're actually doing http
      if retrieval_method == "http"
        # Set up the appropriate http headers
        headers = {}
        unless self.http_headers.nil?
          headers["If-None-Match"] =
            self.http_headers['etag'] unless self.http_headers['etag'].nil?
          headers["If-Modified-Since"] =
            self.http_headers['last-modified'] unless
            self.http_headers['last-modified'].nil?
        end
        unless FeedTools.configurations[:user_agent].nil?
          headers["User-Agent"] = FeedTools.configurations[:user_agent]
        end

        # The http feed access method
        http_fetch = lambda do |feed_url, request_headers, redirect_limit,
            response_chain, no_headers|
          raise FeedAccessError, 'Redirect too deep' if redirect_limit == 0
          feed_uri = nil
          begin
            feed_uri = URI.parse(feed_url)
          rescue URI::InvalidURIError
            # Uh, maybe try to fix it?
            feed_uri = URI.parse(FeedTools.normalize_url(feed_url))
          end
          
          begin
            # TODO: Proxy host and proxy port would go here if implemented
            http = Net::HTTP.new(feed_uri.host, (feed_uri.port or 80))
            http.start do
              final_uri = feed_uri.path 
              final_uri += ('?' + feed_uri.query) if feed_uri.query
              request_headers = {} if no_headers
              response = http.request_get(final_uri, request_headers)

              case response
              when Net::HTTPSuccess
                # We've reached the final destination, process all previous
                # redirections, and see if we need to update the url.
                for redirected_response in response_chain
                  if redirected_response.last.code.to_i == 301
                    # Reset the cache object or we may get duplicate entries
                    self.cache_object = nil
                    self.url = redirected_response.last['location']
                  else
                    # Jump out as soon as we hit anything that isn't a
                    # permanently moved redirection.
                    break
                  end
                end
                response
              when Net::HTTPRedirection
                if response.code.to_i == 304
                  response.error!
                else
                  if response['location'].nil?
                    raise FeedAccessError,
                      "No location to redirect to supplied: " + response.code
                  end
                  response_chain << [feed_url, response]
                  new_location = response['location']
                  if response_chain.assoc(new_location) != nil
                    raise FeedAccessError,
                      "Redirection loop detected: #{new_location}"
                  end
              
                  # Find out if we've already seen the url we've been
                  # redirected to.
                  found_redirect = false
                  begin
                    cached_feed = FeedTools::Feed.open(new_location,
                      :cache_only => true)
                    if cached_feed.cache_object != nil &&
                        cached_feed.cache_object.new_record? != true
                      if !cached_feed.expired? &&
                          !cached_feed.http_headers.blank?
                        # Copy the cached state
                        self.url = cached_feed.url

                        @feed_data = cached_feed.feed_data
                        @feed_data_type = cached_feed.feed_data_type

                        if @feed_data.blank?
                          raise "Invalid cache data."
                        end

                        @title = nil; self.title
                        @link = nil; self.link
                        
                        self.last_retrieved = cached_feed.last_retrieved
                        self.http_headers = cached_feed.http_headers
                        self.cache_object = cached_feed.cache_object
                        @live = false
                        found_redirect = true
                      end
                    end
                  rescue
                    # If anything goes wrong, ignore it.
                  end
                  unless found_redirect
                    # TODO: deal with stupid people using relative urls
                    # in Location header
                    # =================================================
                    http_fetch.call(new_location, http_headers,
                      redirect_limit - 1, response_chain, no_headers)
                  else
                    response
                  end
                end
              else
                class << response
                  def response_chain
                    return @response_chain
                  end
                end
                response.instance_variable_set("@response_chain",
                  response_chain)
                response.error!
              end
            end
          rescue SocketError
            raise FeedAccessError, 'Socket error prevented feed retrieval'
          rescue Timeout::Error
            raise FeedAccessError, 'Timeout while attempting to retrieve feed'
          rescue Errno::ENETUNREACH
            raise FeedAccessError, 'Network was unreachable'
          rescue Errno::ECONNRESET
            raise FeedAccessError, 'Connection was reset by peer'
          end
        end
      
        begin
          begin
            @http_response = http_fetch.call(self.url, headers, 10, [], false)
          rescue => error
            if error.respond_to?(:response)
              # You might not believe this, but...
              #
              # Under certain circumstances, web servers will try to block
              # based on the User-Agent header.  This is *retarded*.  But
              # we won't let their stupid error stop us!
              #
              # This is, of course, a quick-n-dirty hack.  But at least
              # we get to blame other people's bad software and/or bad
              # configuration files.
              if error.response.code.to_i == 404 &&
                  FeedTools.user_agent != nil
                @http_response = http_fetch.call(self.url, {}, 10, [], true)
                if @http_response != nil && @http_response.code.to_i == 200
                  warn("The server appears to be blocking based on the " +
                    "User-Agent header.  This is stupid, and you should " +
                    "inform the webmaster of this.")
                end
              else
                raise error
              end
            else
              raise error
            end
          end
          unless @http_response.kind_of? Net::HTTPRedirection
            @feed_data = self.http_response.body
            @http_headers = {}
            self.http_response.each_header do |key, value|
              self.http_headers[key.downcase] = value
            end
            self.last_retrieved = Time.now.gmtime
          end
        rescue FeedAccessError
          @live = false
          if self.feed_data.nil?
            raise
          end
        rescue Timeout::Error
          # if we time out, do nothing, it should fall back to the feed_data
          # stored in the cache.
          @live = false
          if self.feed_data.nil?
            raise
          end
        rescue Errno::ECONNRESET
          # if the connection gets reset by peer, oh well, fall back to the
          # feed_data stored in the cache
          @live = false
          if self.feed_data.nil?
            raise
          end
        rescue => error
          # heck, if anything at all bad happens, fall back to the feed_data
          # stored in the cache.
        
          # If we can, get the HTTPResponse...
          @http_response = nil
          if error.respond_to?(:each_header)
            @http_response = error
          end
          if error.respond_to?(:response) &&
              error.response.respond_to?(:each_header)
            @http_response = error.response
          end
          if @http_response != nil
            @http_headers = {}
            self.http_response.each_header do |key, value|
              self.http_headers[key.downcase] = value
            end
            if self.http_response.code.to_i == 304
              self.last_retrieved = Time.now.gmtime
            end
          end
          @live = false
          if self.feed_data.nil?
            if error.respond_to?(:response) &&
                error.response.respond_to?(:response_chain)
              redirects = error.response.response_chain.map do |pair|
                pair.first
              end
              error.message << (" - Redirects: " + redirects.inspect)
            end
            raise error
          end
        end
      elsif retrieval_method == "https"
        # Not supported... yet
      elsif retrieval_method == "ftp"
        # Not supported... yet
        # Technically, CDF feeds are supposed to be able to be accessed directly
        # from an ftp server.  This is silly, but we'll humor Microsoft.
        #
        # Eventually.
      elsif retrieval_method == "file"
        # Now that we've gone to all that trouble to ensure the url begins
        # with 'file://', strip the 'file://' off the front of the url.
        file_name = self.url.gsub(/^file:\/\//, "")
        begin
          open(file_name) do |file|
            @http_response = nil
            @http_headers = {}
            @feed_data = file.read
            @feed_data_type = :xml
            self.last_retrieved = Time.now.gmtime
          end
        rescue
          @live = false
          # In this case, pulling from the cache is probably not going
          # to help at all, and the use should probably be immediately
          # appraised of the problem.  Raise the exception.
          raise
        end
      end
      unless self.cache_object.nil?
        begin
          self.save
        rescue
        end
      end
    end
      
    # Returns the relevant information from an http request.
    def http_response
      return @http_response
    end

    # Returns a hash of the http headers from the response.
    def http_headers
      if @http_headers.blank?
        if !self.cache_object.nil? && !self.cache_object.http_headers.nil?
          @http_headers = YAML.load(self.cache_object.http_headers)
          @http_headers = {} unless @http_headers.kind_of? Hash
        else
          @http_headers = {}
        end
      end
      return @http_headers
    end
    
    # Returns the encoding that the feed was parsed with
    def encoding
      if @encoding.nil?
        unless self.http_headers.blank?
          @encoding = "utf-8"
        else
          @encoding = self.encoding_from_xml_data
        end
      end
      return @encoding
    end
    
    # Returns the encoding of feed calculated only from the xml data.
    # I.e., the encoding we would come up with if we ignore RFC 3023.
    def encoding_from_xml_data
      if @encoding_from_xml_data.nil?
        raw_data = self.feed_data
        encoding_from_xml_instruct = 
          raw_data.scan(
            /^<\?xml [^>]*encoding="([\w]*)"[^>]*\?>/
          ).flatten.first
        unless encoding_from_xml_instruct.blank?
          encoding_from_xml_instruct.downcase!
        end
        if encoding_from_xml_instruct.blank?
          doc = Document.new(raw_data)
          encoding_from_xml_instruct = doc.encoding.downcase
          if encoding_from_xml_instruct == "utf-8"
            # REXML has a tendency to report utf-8 overzealously, take with
            # grain of salt
            encoding_from_xml_instruct = nil
          end
        else
          @encoding_from_xml_data = encoding_from_xml_instruct
        end
        if encoding_from_xml_instruct.blank?
          sniff_table = {
            "Lo\247\224" => "ebcdic-cp-us",
            "<?xm" => "utf-8"
          }
          sniff = self.feed_data[0..3]
          if sniff_table[sniff] != nil
            @encoding_from_xml_data = sniff_table[sniff].downcase
          end
        else
          @encoding_from_xml_data = encoding_from_xml_instruct
        end
        if @encoding_from_xml_data.blank?
          # Safest assumption
          @encoding_from_xml_data = "utf-8"
        end
      end
      return @encoding_from_xml_data
    end
  
    # Returns the feed's raw data.
    def feed_data
      if @feed_data.nil?
        unless self.cache_object.nil?
          @feed_data = self.cache_object.feed_data
        end
      end
      return @feed_data
    end
  
    # Sets the feed's data.
    def feed_data=(new_feed_data)
      @http_headers = {}
      @cache_object = nil
      @url = nil
      @id = nil
      @encoding = nil
      @feed_data = new_feed_data
      unless self.cache_object.nil?
        self.cache_object.feed_data = new_feed_data
      end
    end
    
    # Returns the feed's raw data as utf-8.
    def feed_data_utf_8(force_encoding=nil)
      if @feed_data_utf_8.nil?
        raw_data = self.feed_data
        if force_encoding.nil?
          use_encoding = self.encoding
        else
          use_encoding = force_encoding
        end
        if use_encoding != "utf-8"
          begin
            @feed_data_utf_8 =
              Iconv.new('utf-8', use_encoding).iconv(raw_data)
          rescue
            return raw_data
          end
        else
          return self.feed_data
        end
      end
      return @feed_data_utf_8
    end
    
    # Returns the data type of the feed
    # Possible values:
    # * :xml
    # * :yaml
    # * :text
    def feed_data_type
      if @feed_data_type.nil?
        # Right now, nothing else is supported
        @feed_data_type = :xml
      end
      return @feed_data_type
    end

    # Sets the feed's data type.
    def feed_data_type=(new_feed_data_type)
      @feed_data_type = new_feed_data_type
      unless self.cache_object.nil?
        self.cache_object.feed_data_type = new_feed_data_type
      end
    end
  
    # Returns a REXML Document of the feed_data
    def xml
      if self.feed_data_type != :xml
        @xml_doc = nil
      else
        if @xml_doc.nil?
          begin
            begin
              @xml_doc = Document.new(self.feed_data_utf_8,
                :ignore_whitespace_nodes => :all)
            rescue Object
              # Something failed, attempt to repair the xml with htree.
              @xml_doc = HTree.parse(self.feed_data_utf_8).to_rexml
            end
          rescue Object
            @xml_doc = nil
          end
        end
      end
      return @xml_doc
    end
  
    # Returns the first node within the channel_node that matches the xpath
    # query.
    def find_node(xpath, select_result_value=false)
      if self.feed_data_type != :xml
        raise "The feed data type is not xml."
      end
      return try_xpaths(self.channel_node, [xpath],
        :select_result_value => select_result_value)
    end
  
    # Returns all nodes within the channel_node that match the xpath query.
    def find_all_nodes(xpath, select_result_value=false)
      if self.feed_data_type != :xml
        raise "The feed data type is not xml."
      end
      return try_xpaths_all(self.channel_node, [xpath],
        :select_result_value => select_result_value)
    end
  
    # Returns the root node of the feed.
    def root_node
      if @root_node.nil?
        # TODO: Fix this so that added content at the end of the file doesn't
        # break this stuff.
        # E.g.: http://smogzer.tripod.com/smog.rdf
        # ===================================================================
        begin
          if xml.nil?
            return nil
          else
            @root_node = xml.root
          end
        rescue
          return nil
        end
      end
      return @root_node
    end
  
    # Returns the channel node of the feed.
    def channel_node
      if @channel_node.nil? && root_node != nil
        @channel_node = try_xpaths(root_node, [
          "channel",
          "CHANNEL",
          "feedinfo"
        ])
        if @channel_node == nil
          @channel_node = root_node
        end
      end
      return @channel_node
    end
  
    # The cache object that handles the feed persistence.
    def cache_object
      if !@url.nil? && @url =~ /^file:\/\//
        return nil
      end
      unless FeedTools.feed_cache.nil?
        if @cache_object.nil?
          begin
            if @url != nil
              @cache_object = FeedTools.feed_cache.find_by_url(@url)
            end
            if @cache_object.nil?
              @cache_object = FeedTools.feed_cache.new
            end
          rescue
          end      
        end
      end
      return @cache_object
    end
  
    # Sets the cache object for this feed.
    #
    # This can be any object, but it must accept the following messages:
    # url
    # url=
    # title
    # title=
    # link
    # link=
    # feed_data
    # feed_data=
    # feed_data_type
    # feed_data_type=
    # etag
    # etag=
    # last_modified
    # last_modified=
    # save
    def cache_object=(new_cache_object)
      @cache_object = new_cache_object
    end
  
    # Returns the type of feed
    # Possible values:
    # "rss", "atom", "cdf", "!okay/news"
    def feed_type
      if @feed_type.nil?
        if self.root_node.nil?
          return nil
        end
        case self.root_node.name.downcase
        when "feed"
          @feed_type = "atom"
        when "rdf:rdf"
          @feed_type = "rss"
        when "rdf"
          @feed_type = "rss"
        when "rss"
          @feed_type = "rss"
        when "channel"
          @feed_type = "cdf"
        end
      end
      return @feed_type
    end
  
    # Sets the default feed type
    def feed_type=(new_feed_type)
      @feed_type = new_feed_type
    end
  
    # Returns the version number of the feed type.
    # Intentionally does not differentiate between the Netscape and Userland
    # versions of RSS 0.91.
    def feed_version
      if @feed_version.nil?
        if self.root_node.nil?
          return nil
        end
        version = nil
        begin
          version = XPath.first(root_node, "@version").to_s.strip.to_f
        rescue
        end
        version = nil if version == 0.0
        default_namespace = XPath.first(root_node, "@xmlns").to_s.strip
        case self.feed_type
        when "atom"
          if default_namespace == "http://www.w3.org/2005/Atom"
            @feed_version = 1.0
          elsif version != nil
            @feed_version = version
          elsif default_namespace == "http://purl.org/atom/ns#"
            @feed_version = 0.3
          end
        when "rss"
          if default_namespace == "http://my.netscape.com/rdf/simple/0.9/"
            @feed_version = 0.9
          elsif default_namespace == "http://purl.org/rss/1.0/"
            @feed_version = 1.0
          elsif default_namespace == "http://purl.org/net/rss1.1#"
            @feed_version = 1.1
          elsif version != nil
            case version
            when 2.1
              @feed_version = 2.0
            when 2.01
              @feed_version = 2.0
            else
              @feed_version = version
            end
          end
        when "cdf"
          @feed_version = 0.4
        when "!okay/news"
          @feed_version = nil
        end
      end
      return @feed_version
    end

    # Sets the default feed version
    def feed_version=(new_feed_version)
      @feed_version = new_feed_version
    end

    # Returns the feed's unique id
    def id
      if @id.nil?
        @id = select_not_blank([
          try_xpaths(self.channel_node, [
            "atom10:id/text()",
            "atom03:id/text()",
            "atom:id/text()",
            "id/text()",
            "guid/text()"
          ], :select_result_value => true),
          try_xpaths(self.root_node, [
            "atom10:id/text()",
            "atom03:id/text()",
            "atom:id/text()",
            "id/text()",
            "guid/text()"
          ], :select_result_value => true)
        ])
      end
      return @id
    end
  
    # Sets the feed's unique id
    def id=(new_id)
      @id = new_id
    end
  
    # Returns the feed url.
    def url
      original_url = @url
      override_url = lambda do |result|
        begin
          if result.nil? && self.feed_data != nil
            true
          elsif result != nil &&
              !(["http", "https"].include?(URI.parse(result.to_s).scheme))
            if self.feed_data != nil
              true
            else
              false
            end
          else
            false
          end
        rescue
          true
        end
      end
      if override_url.call(@url)
        # rdf:about is ordered last because a lot of people accidentally
        # put the link in that field instead of the url to the feed.
        # Ordering it last gives them as many chances as humanly possible
        # for them to redeem themselves.  If the link turns out to be the
        @url = try_xpaths(self.channel_node, [
          "link[@rel='self']/@href",
          "atom10:link[@rel='self']/@href",
          "atom03:link[@rel='self']/@href",
          "atom:link[@rel='self']/@href",
          "admin:feed/@rdf:resource",
          "admin:feed/@resource",
          "feed/@rdf:resource",
          "feed/@resource",
          "@rdf:about",
          "@about"
        ], :select_result_value => true) do |result|
          override_url.call(FeedTools.normalize_url(result))
        end
        @url = FeedTools.normalize_url(@url)
        if @url == nil
          @url = original_url
        end
        if @url == self.link
          @url = original_url
        end
      end
      return @url
    end
  
    # Sets the feed url and prepares the cache_object if necessary.
    def url=(new_url)
      @url = FeedTools.normalize_url(new_url)
      self.cache_object.url = new_url unless self.cache_object.nil?
    end
  
    # Returns the feed title
    def title
      if @title.nil?
        repair_entities = false
        title_node = try_xpaths(self.channel_node, [
          "atom10:title",
          "atom03:title",
          "atom:title",
          "title",
          "dc:title"
        ])
        if title_node.nil?
          return nil
        end
        title_type = try_xpaths(title_node, "@type",
          :select_result_value => true)
        title_mode = try_xpaths(title_node, "@mode",
          :select_result_value => true)
        title_encoding = try_xpaths(title_node, "@encoding",
          :select_result_value => true)
        
        # Note that we're checking for misuse of type, mode and encoding here
        if title_type == "base64" || title_mode == "base64" ||
            title_encoding == "base64"
          @title = Base64.decode64(title_node.inner_xml.strip)
        elsif title_type == "xhtml" || title_mode == "xhtml" ||
            title_type == "xml" || title_mode == "xml" ||
            title_type == "application/xhtml+xml"
          @title = title_node.inner_xml
        elsif title_type == "escaped" || title_mode == "escaped"
          @title = FeedTools.unescape_entities(
            title_node.inner_xml)
        else
          @title = title_node.inner_xml
          repair_entities = true
        end
        unless @title.nil?
          @title = FeedTools.sanitize_html(@title, :strip)
          @title = FeedTools.unescape_entities(@title) if repair_entities
          @title = FeedTools.tidy_html(@title) unless repair_entities
        end
        @title.gsub!(/>\n</, "><")
        @title.gsub!(/\n/, " ")
        @title.strip!
        @title = nil if @title.blank?
        self.cache_object.title = @title unless self.cache_object.nil?
      end
      return @title
    end
  
    # Sets the feed title
    def title=(new_title)
      @title = new_title
      self.cache_object.title = new_title unless self.cache_object.nil?
    end

    # Returns the feed subtitle
    def subtitle
      if @subtitle.nil?
        repair_entities = false
        subtitle_node = try_xpaths(self.channel_node, [
          "atom10:subtitle",
          "subtitle",
          "atom03:tagline",
          "tagline",
          "description",
          "summary",
          "abstract",
          "ABSTRACT",
          "content:encoded",
          "encoded",
          "content",
          "xhtml:body",
          "body",
          "blurb",
          "info"
        ])
        if subtitle_node.nil?
          return nil
        end
        subtitle_type = try_xpaths(subtitle_node, "@type",
          :select_result_value => true)
        subtitle_mode = try_xpaths(subtitle_node, "@mode",
          :select_result_value => true)
        subtitle_encoding = try_xpaths(subtitle_node, "@encoding",
          :select_result_value => true)

        # Note that we're checking for misuse of type, mode and encoding here
        if !subtitle_encoding.blank?
          @subtitle =
            "[Embedded data objects are not currently supported.]"
        elsif subtitle_node.cdatas.size > 0
          @subtitle = subtitle_node.cdatas.first.value
        elsif subtitle_type == "base64" || subtitle_mode == "base64" ||
            subtitle_encoding == "base64"
          @subtitle = Base64.decode64(subtitle_node.inner_xml.strip)
        elsif subtitle_type == "xhtml" || subtitle_mode == "xhtml" ||
            subtitle_type == "xml" || subtitle_mode == "xml" ||
            subtitle_type == "application/xhtml+xml"
          @subtitle = subtitle_node.inner_xml
        elsif subtitle_type == "escaped" || subtitle_mode == "escaped"
          @subtitle = FeedTools.unescape_entities(
            subtitle_node.inner_xml)
        else
          @subtitle = subtitle_node.inner_xml
          repair_entities = true
        end
        if @subtitle.blank?
          @subtitle = self.itunes_summary
        end
        if @subtitle.blank?
          @subtitle = self.itunes_subtitle
        end

        unless @subtitle.blank?
          @subtitle = FeedTools.sanitize_html(@subtitle, :strip)
          @subtitle = FeedTools.unescape_entities(@subtitle) if repair_entities
          @subtitle = FeedTools.tidy_html(@subtitle)
        end

        @subtitle = @subtitle.strip unless @subtitle.nil?
        @subtitle = nil if @subtitle.blank?
      end
      return @subtitle
    end

    # Sets the feed subtitle
    def subtitle=(new_subtitle)
      @subtitle = new_subtitle
    end

    # Returns the contents of the itunes:summary element
    def itunes_summary
      if @itunes_summary.nil?
        @itunes_summary = select_not_blank([
          try_xpaths(self.channel_node, [
            "itunes:summary/text()"
          ]),
          try_xpaths(self.root_node, [
            "itunes:summary/text()"
          ])
        ])
        unless @itunes_summary.blank?
          @itunes_summary = FeedTools.unescape_entities(@itunes_summary)
          @itunes_summary = FeedTools.sanitize_html(@itunes_summary)
        else
          @itunes_summary = nil
        end
      end
      return @itunes_summary
    end

    # Sets the contents of the itunes:summary element
    def itunes_summary=(new_itunes_summary)
      @itunes_summary = new_itunes_summary
    end

    # Returns the contents of the itunes:subtitle element
    def itunes_subtitle
      if @itunes_subtitle.nil?
        @itunes_subtitle = select_not_blank([
          try_xpaths(self.channel_node, [
            "itunes:subtitle/text()"
          ]),
          try_xpaths(self.root_node, [
            "itunes:subtitle/text()"
          ])
        ])
        unless @itunes_subtitle.blank?
          @itunes_subtitle = FeedTools.unescape_entities(@itunes_subtitle)
          @itunes_subtitle = FeedTools.sanitize_html(@itunes_subtitle)
        else
          @itunes_subtitle = nil
        end
      end
      return @itunes_subtitle
    end

    # Sets the contents of the itunes:subtitle element
    def itunes_subtitle=(new_itunes_subtitle)
      @itunes_subtitle = new_itunes_subtitle
    end

    # Returns the feed link
    def link
      if @link.nil?
        @link = try_xpaths(self.channel_node, [
          "atom10:link[@type='application/xhtml+xml']/@href",
          "atom10:link[@type='text/html']/@href",
          "atom10:link[@rel='alternate']/@href",
          "atom03:link[@type='application/xhtml+xml']/@href",
          "atom03:link[@type='text/html']/@href",
          "atom03:link[@rel='alternate']/@href",
          "atom:link[@type='application/xhtml+xml']/@href",
          "atom:link[@type='text/html']/@href",
          "atom:link[@rel='alternate']/@href",
          "link[@type='application/xhtml+xml']/@href",
          "link[@type='text/html']/@href",
          "link[@rel='alternate']/@href",
          "link/text()",
          "@href",
          "a/@href"
        ], :select_result_value => true)
        if @link.blank?
          if FeedTools.is_uri?(self.guid) &&
              !(self.guid =~ /^urn:uuid:/) &&
              !(self.guid =~ /^tag:/)
            @link = self.guid
          end
        end
        if @link.blank? && channel_node != nil
          # Technically, we shouldn't use the base attribute for this, but
          # if the href attribute is missing, it's already a given that we're
          # looking at a messed up CDF file.  We can always pray it's correct.
          @link = XPath.first(channel_node, "@base").to_s
        end
        if !@link.blank?
          @link = FeedTools.unescape_entities(@link)
        end
        if @link.blank?
          link_node = try_xpaths(self.channel_node, [
            "atom10:link",
            "atom03:link",
            "atom:link",
            "link"
          ])
          if link_node != nil
            if link_node.attributes['type'].to_s =~ /^image/ ||
                link_node.attributes['type'].to_s =~ /^application/ || 
                link_node.attributes['type'].to_s =~ /xml/ ||
                link_node.attributes['rel'].to_s =~ /self/
              for child in self.channel_node
                if child.class == REXML::Element
                  if child.name.downcase == "link"
                    if child.attributes['type'].to_s =~ /^image/ ||
                        child.attributes['type'].to_s =~ /^application/ || 
                        child.attributes['type'].to_s =~ /xml/ ||
                        child.attributes['rel'].to_s =~ /self/
                      @link = nil
                      next
                    else
                      @link = child.attributes['href'].to_s
                      if @link.blank?
                        @link = child.inner_xml
                      end
                      if @link.blank?
                        next
                      end
                      break
                    end
                  end
                end
              end
            else
              @link = link_node.attributes['href'].to_s
            end
          end
        end
        @link = nil if @link.blank?
        if FeedTools.configurations[:url_normalization_enabled]
          @link = FeedTools.normalize_url(@link)
        end
        unless self.cache_object.nil?
          self.cache_object.link = @link
        end
      end
      return @link
    end

    # Sets the feed link
    def link=(new_link)
      @link = new_link
      unless self.cache_object.nil?
        self.cache_object.link = new_link
      end
    end

    # Returns the url to the icon file for this feed.
    def icon
      if @icon.nil?
        icon_node = try_xpaths(self.channel_node, [
          "link[@rel='icon']",
          "link[@rel='shortcut icon']",
          "link[@type='image/x-icon']",
          "icon",
          "logo[@style='icon']",
          "LOGO[@STYLE='ICON']"
        ])
        unless icon_node.nil?
          @icon = FeedTools.unescape_entities(
            XPath.first(icon_node, "@href").to_s)
          if @icon.blank?
            @icon = FeedTools.unescape_entities(
              XPath.first(icon_node, "text()").to_s)
            unless FeedTools.is_uri? @icon
              @icon = nil
            end
          end
          @icon = nil if @icon.blank?
        end
      end
      return @icon
    end
    
    # Returns the favicon url for this feed.
    # This method first tries to use the url from the link field instead of
    # the feed url, in order to avoid grabbing the favicon for services like
    # feedburner.
    def favicon
      if @favicon.nil?
        if !self.link.blank?
          begin
            link_uri = URI.parse(FeedTools.normalize_url(self.link))
            if link_uri.scheme == "http"
              @favicon =
                "http://" + link_uri.host + "/favicon.ico"
            end
          rescue
            @favicon = nil
          end
          if @favicon.nil? && !self.url.blank?
            begin
              feed_uri = URI.parse(FeedTools.normalize_url(self.url))
              if feed_uri.scheme == "http"
                @favicon =
                  "http://" + feed_uri.host + "/favicon.ico"
              end
            rescue
              @favicon = nil
            end
          end
        else
          @favicon = nil
        end
      end
      return @favicon
    end

    # Returns the feed author
    def author
      if @author.nil?
        @author = FeedTools::Feed::Author.new
        author_node = try_xpaths(self.channel_node, [
          "atom10:author",
          "atom03:author",
          "atom:author",
          "author",
          "managingEditor",
          "dc:author",
          "dc:creator"
        ])
        unless author_node.nil?
          @author.raw = FeedTools.unescape_entities(
            XPath.first(author_node, "text()").to_s).strip
          @author.raw = nil if @author.raw.blank?
          unless @author.raw.nil?
            raw_scan = @author.raw.scan(
              /(.*)\((\b[A-Z0-9._%-\+]+@[A-Z0-9._%-]+\.[A-Z]{2,4}\b)\)/i)
            if raw_scan.nil? || raw_scan.size == 0
              raw_scan = @author.raw.scan(
                /(\b[A-Z0-9._%-\+]+@[A-Z0-9._%-]+\.[A-Z]{2,4}\b)\s*\((.*)\)/i)
              author_raw_pair = raw_scan.first.reverse unless raw_scan.size == 0
            else
              author_raw_pair = raw_scan.first
            end
            if raw_scan.nil? || raw_scan.size == 0
              email_scan = @author.raw.scan(
                /\b[A-Z0-9._%-\+]+@[A-Z0-9._%-]+\.[A-Z]{2,4}\b/i)
              if email_scan != nil && email_scan.size > 0
                @author.email = email_scan.first.strip
              end
            end
            unless author_raw_pair.nil? || author_raw_pair.size == 0
              @author.name = author_raw_pair.first.strip
              @author.email = author_raw_pair.last.strip
            else
              unless @author.raw.include?("@")
                # We can be reasonably sure we are looking at something
                # that the creator didn't intend to contain an email address if
                # it got through the preceeding regexes and it doesn't
                # contain the tell-tale '@' symbol.
                @author.name = @author.raw
              end
            end
          end
          if @author.name.blank?
            @author.name = FeedTools.unescape_entities(
              try_xpaths(author_node, [
                "atom10:name/text()",
                "atom03:name/text()",
                "atom:name/text()",
                "name/text()",
                "@name"
              ], :select_result_value => true)
            )
          end
          if @author.email.blank?
            @author.email = FeedTools.unescape_entities(
              try_xpaths(author_node, [
                "atom10:email/text()",
                "atom03:email/text()",
                "atom:email/text()",
                "email/text()",
                "@email"
              ], :select_result_value => true)
            )
          end
          if @author.url.blank?
            @author.url = FeedTools.unescape_entities(
              try_xpaths(author_node, [
                "atom10:url/text()",
                "atom03:url/text()",
                "atom:url/text()",
                "url/text()",
                "atom10:uri/text()",
                "atom03:uri/text()",
                "atom:uri/text()",
                "uri/text()",
                "@url",
                "@uri",
                "@href"
              ], :select_result_value => true)
            )
          end
          @author.name = nil if @author.name.blank?
          @author.raw = nil if @author.raw.blank?
          @author.email = nil if @author.email.blank?
          @author.url = nil if @author.url.blank?
        end
        # Fallback on the itunes module if we didn't find an author name
        begin
          @author.name = self.itunes_author if @author.name.nil?
        rescue
          @author.name = nil
        end
      end
      return @author
    end

    # Sets the feed author
    def author=(new_author)
      if new_author.respond_to?(:name) &&
          new_author.respond_to?(:email) &&
          new_author.respond_to?(:url)
        # It's a complete author object, just set it.
        @author = new_author
      else
        # We're not looking at an author object, this is probably a string,
        # default to setting the author's name.
        if @author.nil?
          @author = FeedTools::Feed::Author.new
        end
        @author.name = new_author
      end
    end

    # Returns the feed publisher
    def publisher
      if @publisher.nil?
        @publisher = FeedTools::Feed::Author.new
        publisher_node = try_xpaths(self.channel_node, [
          "webMaster/text()",
          "dc:publisher/text()"
        ])

        # Set the author name
        @publisher.raw = FeedTools.unescape_entities(publisher_node.to_s)
        unless @publisher.raw.blank?
          raw_scan = @publisher.raw.scan(
            /(.*)\((\b[A-Z0-9._%-\+]+@[A-Z0-9._%-]+\.[A-Z]{2,4}\b)\)/i)
          if raw_scan.nil? || raw_scan.size == 0
            raw_scan = @publisher.raw.scan(
              /(\b[A-Z0-9._%-\+]+@[A-Z0-9._%-]+\.[A-Z]{2,4}\b)\s*\((.*)\)/i)
            unless raw_scan.size == 0
              publisher_raw_pair = raw_scan.first.reverse
            end
          else
            publisher_raw_pair = raw_scan.first
          end
          if raw_scan.nil? || raw_scan.size == 0
            email_scan = @publisher.raw.scan(
              /\b[A-Z0-9._%-\+]+@[A-Z0-9._%-]+\.[A-Z]{2,4}\b/i)
            if email_scan != nil && email_scan.size > 0
              @publisher.email = email_scan.first.strip
            end
          end
          unless publisher_raw_pair.nil? || publisher_raw_pair.size == 0
            @publisher.name = publisher_raw_pair.first.strip
            @publisher.email = publisher_raw_pair.last.strip
          else
            unless @publisher.raw.include?("@")
              # We can be reasonably sure we are looking at something
              # that the creator didn't intend to contain an email address if
              # it got through the preceeding regexes and it doesn't
              # contain the tell-tale '@' symbol.
              @publisher.name = @publisher.raw
            end
          end
        end

        @publisher.name = nil if @publisher.name.blank?
        @publisher.raw = nil if @publisher.raw.blank?
        @publisher.email = nil if @publisher.email.blank?
        @publisher.url = nil if @publisher.url.blank?
      end
      return @publisher
    end

    # Sets the feed publisher
    def publisher=(new_publisher)
      if new_publisher.respond_to?(:name) &&
          new_publisher.respond_to?(:email) &&
          new_publisher.respond_to?(:url)
        # It's a complete Author object, just set it.
        @publisher = new_publisher
      else
        # We're not looking at an Author object, this is probably a string,
        # default to setting the publisher's name.
        if @publisher.nil?
          @publisher = FeedTools::Feed::Author.new
        end
        @publisher.name = new_publisher
      end
    end
  
    # Returns the contents of the itunes:author element
    #
    # Returns any incorrectly placed channel-level itunes:author
    # elements.  They're actually amazingly common.  People don't read specs.
    # There is no setter for this, since this is an incorrectly placed
    # attribute.
    def itunes_author
      if @itunes_author.nil?
        @itunes_author = FeedTools.unescape_entities(
          try_xpaths(self.channel_node, [
            "itunes:author/text()"
          ], :select_result_value => true)
        )
        @itunes_author = nil if @itunes_author.blank?
      end
      return @itunes_author
    end

    # Returns the feed time
    def time
      if @time.nil?
        time_string = try_xpaths(self.channel_node, [
          "atom10:updated/text()",
          "atom03:updated/text()",
          "atom:updated/text()",
          "updated/text()",
          "atom10:modified/text()",
          "atom03:modified/text()",
          "atom:modified/text()",
          "modified/text()",
          "time/text()",
          "atom10:issued/text()",
          "atom03:issued/text()",
          "atom:issued/text()",
          "issued/text()",
          "atom10:published/text()",
          "atom03:published/text()",
          "atom:published/text()",
          "published/text()",
          "pubDate/text()",
          "dc:date/text()",
          "date/text()"
        ], :select_result_value => true)
        begin
          unless time_string.blank?
            @time = Time.parse(time_string).gmtime
          else
            if FeedTools.configurations[:timestamp_estimation_enabled]
              @time = Time.now.gmtime
            end
          end
        rescue
          if FeedTools.configurations[:timestamp_estimation_enabled]
            @time = Time.now.gmtime
          end
        end
      end
      return @time
    end
  
    # Sets the feed item time
    def time=(new_time)
      @time = new_time
    end
  
    # Returns the feed item updated time
    def updated
      if @updated.nil?
        updated_string = try_xpaths(self.channel_node, [
          "atom10:updated/text()",
          "atom03:updated/text()",
          "atom:updated/text()",
          "updated/text()",
          "atom10:modified/text()",
          "atom03:modified/text()",
          "atom:modified/text()",
          "modified/text()"
        ], :select_result_value => true)
        unless updated_string.blank?
          @updated = Time.parse(updated_string).gmtime rescue nil
        else
          @updated = nil
        end
      end
      return @updated
    end
  
    # Sets the feed item updated time
    def updated=(new_updated)
      @updated = new_updated
    end

    # Returns the feed item published time
    def published
      if @published.nil?
        published_string = try_xpaths(self.channel_node, [
          "atom10:published/text()",
          "atom03:published/text()",
          "atom:published/text()",
          "published/text()",
          "pubDate/text()",
          "atom10:issued/text()",
          "atom03:issued/text()",
          "atom:issued/text()",
          "issued/text()",
          "dc:date/text()"
        ], :select_result_value => true)
        unless published_string.blank?
          @published = Time.parse(published_string).gmtime rescue nil
        else
          @published = nil
        end
      end
      return @published
    end
  
    # Sets the feed item published time
    def published=(new_published)
      @published = new_published
    end

    # Returns a list of the feed's categories
    def categories
      if @categories.nil?
        @categories = []
        category_nodes = try_xpaths_all(self.channel_node, [
          "category",
          "dc:subject"
        ])
        unless category_nodes.nil?
          for category_node in category_nodes
            category = FeedTools::Feed::Category.new
            category.term = try_xpaths(category_node, [
              "@term",
              "text()"
            ], :select_result_value => true)
            category.term.strip! unless category.term.blank?
            category.label = try_xpaths(category_node, ["@label"],
              :select_result_value => true)
            category.label.strip! unless category.label.blank?
            category.scheme = try_xpaths(category_node, [
              "@scheme",
              "@domain"
            ], :select_result_value => true)
            category.scheme.strip! unless category.scheme.blank?
            @categories << category
          end
        end
      end
      return @categories
    end
  
    # Returns a list of the feed's images
    def images
      if @images.nil?
        @images = []
        image_nodes = try_xpaths_all(self.channel_node, [
          "image",
          "logo",
          "apple-wallpapers:image",
          "atom10:link",
          "atom03:link",
          "atom:link",
          "link"
        ])
        unless image_nodes.blank?
          for image_node in image_nodes
            image = FeedTools::Feed::Image.new
            image.url = try_xpaths(image_node, [
              "url/text()",
              "@rdf:resource",
              "text()"
            ], :select_result_value => true)
            if image.url.blank? && (image_node.name == "logo" ||
                (image_node.attributes['type'].to_s =~ /^image/) == 0)
              image.url = try_xpaths(image_node, [
                "@atom10:href",
                "@atom03:href",
                "@atom:href",
                "@href"
              ], :select_result_value => true)
              if image.url == self.link && image.url != nil
                image.url = nil
              end
            end
            if image.url.blank? && image_node.name == "LOGO"
              image.url = try_xpaths(image_node, [
                "@href"
              ], :select_result_value => true)
            end
            image.url.strip! unless image.url.nil?
            image.title = try_xpaths(image_node,
              ["title/text()"], :select_result_value => true)
            image.title.strip! unless image.title.nil?
            image.description = try_xpaths(image_node,
              ["description/text()"], :select_result_value => true)
            image.description.strip! unless image.description.nil?
            image.link = try_xpaths(image_node,
              ["link/text()"], :select_result_value => true)
            image.link.strip! unless image.link.nil?
            image.height = try_xpaths(image_node,
              ["height/text()"], :select_result_value => true).to_i
            image.height = nil if image.height <= 0
            image.width = try_xpaths(image_node,
              ["width/text()"], :select_result_value => true).to_i
            image.width = nil if image.width <= 0
            image.style = try_xpaths(image_node, [
              "style/text()",
              "@style"
            ], :select_result_value => true)
            image.style.strip! unless image.style.nil?
            image.style.downcase! unless image.style.nil?
            @images << image unless image.url.nil?
          end
        end
      end
      return @images
    end
  
    # Returns the feed's text input field
    def text_input
      if @text_input.nil?
        @text_input = FeedTools::Feed::TextInput.new
        text_input_node = try_xpaths(self.channel_node, ["textInput"])
        unless text_input_node.nil?
          @text_input.title =
            try_xpaths(text_input_node, ["title/text()"],
              :select_result_value => true)
          @text_input.description =
            try_xpaths(text_input_node, ["description/text()"],
              :select_result_value => true)
          @text_input.link =
            try_xpaths(text_input_node, ["link/text()"],
              :select_result_value => true)
          @text_input.name =
            try_xpaths(text_input_node, ["name/text()"],
              :select_result_value => true)
        end
      end
      return @text_input
    end
      
    # Returns the feed's copyright information
    def copyright
      if @copyright.nil?
        repair_entities = false
        copyright_node = try_xpaths(self.channel_node, [
          "atom10:copyright",
          "atom03:copyright",
          "atom:copyright",
          "copyright",
          "copyrights",
          "dc:rights",
          "rights"
        ])
        if copyright_node.nil?
          return nil
        end
        copyright_type = try_xpaths(copyright_node, "@type",
          :select_result_value => true)
        copyright_mode = try_xpaths(copyright_node, "@mode",
          :select_result_value => true)
        copyright_encoding = try_xpaths(copyright_node, "@encoding",
          :select_result_value => true)

        # Note that we're checking for misuse of type, mode and encoding here
        if !copyright_encoding.blank?
          @copyright =
            "[Embedded data objects are not currently supported.]"
        elsif copyright_node.cdatas.size > 0
          @copyright = copyright_node.cdatas.first.value
        elsif copyright_type == "base64" || copyright_mode == "base64" ||
            copyright_encoding == "base64"
          @copyright = Base64.decode64(copyright_node.inner_xml.strip)
        elsif copyright_type == "xhtml" || copyright_mode == "xhtml" ||
            copyright_type == "xml" || copyright_mode == "xml" ||
            copyright_type == "application/xhtml+xml"
          @copyright = copyright_node.inner_xml
        elsif copyright_type == "escaped" || copyright_mode == "escaped"
          @copyright = FeedTools.unescape_entities(
            copyright_node.inner_xml)
        else
          @copyright = copyright_node.inner_xml
          repair_entities = true
        end

        unless @copyright.nil?
          @copyright = FeedTools.sanitize_html(@copyright, :strip)
          @copyright = FeedTools.unescape_entities(@copyright) if repair_entities
          @copyright = FeedTools.tidy_html(@copyright)
        end

        @copyright = @copyright.strip unless @copyright.nil?
        @copyright = nil if @copyright.blank?
      end
      return @copyright
    end

    # Sets the feed's copyright information
    def copyright=(new_copyright)
      @copyright = new_copyright
    end

    # Returns the number of seconds before the feed should expire
    def time_to_live
      if @time_to_live.nil?
        unless channel_node.nil?
          # get the feed time to live from the xml document
          update_frequency = try_xpaths(self.channel_node,
            ["syn:updateFrequency/text()"], :select_result_value => true)
          if !update_frequency.blank?
            update_period = try_xpaths(self.channel_node,
              ["syn:updatePeriod/text()"], :select_result_value => true)
            if update_period == "daily"
              @time_to_live = update_frequency.to_i.day
            elsif update_period == "weekly"
              @time_to_live = update_frequency.to_i.week
            elsif update_period == "monthly"
              @time_to_live = update_frequency.to_i.month
            elsif update_period == "yearly"
              @time_to_live = update_frequency.to_i.year
            else
              # hourly
              @time_to_live = update_frequency.to_i.hour
            end
          end
          if @time_to_live.nil?
            # usually expressed in minutes
            update_frequency = try_xpaths(self.channel_node, ["ttl/text()"],
              :select_result_value => true)
            if !update_frequency.blank?
              update_span = try_xpaths(self.channel_node, ["ttl/@span"],
                :select_result_value => true)
              if update_span == "seconds"
                @time_to_live = update_frequency.to_i
              elsif update_span == "minutes"
                @time_to_live = update_frequency.to_i.minute
              elsif update_span == "hours"
                @time_to_live = update_frequency.to_i.hour
              elsif update_span == "days"
                @time_to_live = update_frequency.to_i.day
              elsif update_span == "weeks"
                @time_to_live = update_frequency.to_i.week
              elsif update_span == "months"
                @time_to_live = update_frequency.to_i.month
              elsif update_span == "years"
                @time_to_live = update_frequency.to_i.year
              else
                @time_to_live = update_frequency.to_i.minute
              end
            end
          end
          if @time_to_live.nil?
            @time_to_live = 0
            update_frequency_days =
              XPath.first(channel_node, "SCHEDULE/INTERVALTIME/@DAY").to_s
            update_frequency_hours =
              XPath.first(channel_node, "schedule/intervaltime/@hour").to_s
            update_frequency_minutes =
              XPath.first(channel_node, "schedule/intervaltime/@min").to_s
            update_frequency_seconds =
              XPath.first(channel_node, "schedule/intervaltime/@sec").to_s
            if update_frequency_days != ""
              @time_to_live = @time_to_live + update_frequency_days.to_i.day
            end
            if update_frequency_hours != ""
              @time_to_live = @time_to_live + update_frequency_hours.to_i.hour
            end
            if update_frequency_minutes != ""
              @time_to_live = @time_to_live +
                update_frequency_minutes.to_i.minute
            end
            if update_frequency_seconds != ""
              @time_to_live = @time_to_live + update_frequency_seconds.to_i
            end
            if @time_to_live == 0
              @time_to_live = 1.hour
            end
          end
        end
      end
      if @time_to_live.nil? || @time_to_live == 0
        # Default to one hour
        @time_to_live = 1.hour
      elsif FeedTools.configurations[:max_ttl] != nil &&
          FeedTools.configurations[:max_ttl] != 0 &&
          @time_to_live >= FeedTools.configurations[:max_ttl].to_i
        @time_to_live = FeedTools.configurations[:max_ttl].to_i
      end
      @time_to_live = @time_to_live.round
      return @time_to_live
    end

    # Sets the feed time to live
    def time_to_live=(new_time_to_live)
      @time_to_live = new_time_to_live.round
      @time_to_live = 1.hour if @time_to_live < 1.hour
    end

    # Returns the feed's cloud
    def cloud
      if @cloud.nil?
        @cloud = FeedTools::Feed::Cloud.new
        @cloud.domain = try_xpaths(self.channel_node, ["cloud/@domain"],
          :select_result_value => true)
        @cloud.port = try_xpaths(self.channel_node, ["cloud/@port"],
          :select_result_value => true)
        @cloud.path = try_xpaths(self.channel_node, ["cloud/@path"],
          :select_result_value => true)
        @cloud.register_procedure =
          try_xpaths(self.channel_node, ["cloud/@registerProcedure"],
            :select_result_value => true)
        @cloud.protocol =
          try_xpaths(self.channel_node, ["cloud/@protocol"],
            :select_result_value => true)
        @cloud.protocol.downcase unless @cloud.protocol.nil?
        @cloud.port = @cloud.port.to_s.to_i
        @cloud.port = nil if @cloud.port == 0
      end
      return @cloud
    end
  
    # Sets the feed's cloud
    def cloud=(new_cloud)
      @cloud = new_cloud
    end
  
    # Returns the feed generator
    def generator
      if @generator.nil?
        @generator = try_xpaths(self.channel_node, ["generator/text()"],
          :select_result_value => true)
        @generator = FeedTools.strip_html(@generator) unless @generator.nil?
      end
      return @generator
    end

    # Sets the feed generator
    def generator=(new_generator)
      @generator = new_generator
    end

    # Returns the feed docs
    def docs
      if @docs.nil?
        @docs = try_xpaths(self.channel_node, ["docs/text()"],
          :select_result_value => true)
        @docs = FeedTools.strip_html(@docs) unless @docs.nil?
      end
      return @docs
    end

    # Sets the feed docs
    def docs=(new_docs)
      @docs = new_docs
    end

    # Returns the feed language
    def language
      if @language.nil?
        @language = select_not_blank([
          try_xpaths(self.channel_node, [
            "language/text()",
            "dc:language/text()",
            "@dc:language",
            "@xml:lang",
            "xml:lang/text()"
          ], :select_result_value => true),
          try_xpaths(self.root_node, [
            "@xml:lang",
            "xml:lang/text()"
          ], :select_result_value => true)
        ])
        if @language.blank?
          @language = "en-us"
        end
        @language = @language.downcase
      end
      return @language
    end

    # Sets the feed language
    def language=(new_language)
      @language = new_language
    end
  
    # Returns true if this feed contains explicit material.
    def explicit?
      if @explicit.nil?
        explicit_string = try_xpaths(self.channel_node, [
          "media:adult/text()",
          "itunes:explicit/text()"
        ], :select_result_value => true)
        if explicit_string == "true" || explicit_string == "yes"
          @explicit = true
        else
          @explicit = false
        end
      end
      return @explicit
    end

    # Sets whether or not the feed contains explicit material
    def explicit=(new_explicit)
      @explicit = (new_explicit ? true : false)
    end
  
    # Returns the feed entries
    def entries
      if @entries.blank?
        raw_entries = select_not_blank([
          try_xpaths_all(self.channel_node, [
            "atom10:entry",
            "atom03:entry",
            "atom:entry",
            "entry"
          ]),
          try_xpaths_all(self.root_node, [
            "rss10:item",
            "item",
            "atom10:entry",
            "atom03:entry",
            "atom:entry",
            "entry"
          ]),
          try_xpaths_all(self.channel_node, [
            "rss10:item",
            "item"
          ])
        ])

        # create the individual feed items
        @entries = []
        unless raw_entries.blank?
          for entry_node in raw_entries.reverse
            new_entry = FeedItem.new
            new_entry.feed_data = entry_node.to_s
            new_entry.feed_data_type = self.feed_data_type
            @entries << new_entry
          end
        end
      end
    
      # Sort the items
      @entries = @entries.sort do |a, b|
        (b.time or Time.utc(1970)) <=> (a.time or Time.utc(1970))
      end
      return @entries
    end

    # Sets the entries array to a new array.
    def entries=(new_entries)
      for entry in new_entries
        unless entry.kind_of? FeedTools::FeedItem
          raise ArgumentError,
            "You should only add FeedItem objects to the entries array."
        end
      end
      @entries = new_entries
    end
    
    # Syntactic sugar for appending feed items to a feed.
    def <<(new_entry)
      @entries ||= []
      unless new_entry.kind_of? FeedTools::FeedItem
        raise ArgumentError,
          "You should only add FeedItem objects to the entries array."
      end
      @entries << new_entry
    end
  
    # The time that the feed was last requested from the remote server.  Nil
    # if it has never been pulled, or if it was created from scratch.
    def last_retrieved
      unless self.cache_object.nil?
        @last_retrieved = self.cache_object.last_retrieved
      end
      return @last_retrieved
    end
  
    # Sets the time that the feed was last updated.
    def last_retrieved=(new_last_retrieved)
      @last_retrieved = new_last_retrieved
      unless self.cache_object.nil?
        self.cache_object.last_retrieved = new_last_retrieved
      end
    end
  
    # True if this feed contains audio content enclosures
    def podcast?
      podcast = false
      self.items.each do |item|
        item.enclosures.each do |enclosure|
          podcast = true if enclosure.audio?
        end
      end
      return podcast
    end

    # True if this feed contains video content enclosures
    def vidlog?
      vidlog = false
      self.items.each do |item|
        item.enclosures.each do |enclosure|
          vidlog = true if enclosure.video?
        end
      end
      return vidlog
    end
  
    # True if the feed was not last retrieved from the cache.
    def live?
      return @live
    end
  
    # True if the feed has expired and must be reacquired from the remote
    # server.
    def expired?
      if (self.last_retrieved == nil)
        return true
      elsif (self.time_to_live < 30.minutes)
        return (self.last_retrieved + 30.minutes) < Time.now.gmtime
      else
        return (self.last_retrieved + self.time_to_live) < Time.now.gmtime
      end
    end
  
    # Forces this feed to expire.
    def expire!
      self.last_retrieved = Time.mktime(1970).gmtime
      self.save
    end

    # A hook method that is called during the feed generation process.
    # Overriding this method will enable additional content to be
    # inserted into the feed.
    def build_xml_hook(feed_type, version, xml_builder)
      return nil
    end

    # Generates xml based on the content of the feed
    def build_xml(feed_type=(self.feed_type or "atom"), version=nil,
        xml_builder=Builder::XmlMarkup.new(
          :indent => 2, :escape_attrs => false))
      xml_builder.instruct! :xml, :version => "1.0",
        :encoding => (FeedTools.configurations[:output_encoding] or "utf-8")
      if feed_type == "rss" && (version == nil || version <= 0.0)
        version = 1.0
      elsif feed_type == "atom" && (version == nil || version <= 0.0)
        version = 1.0
      end
      if feed_type == "rss" && (version == 0.9 || version == 1.0 ||
          version == 1.1)
        # RDF-based rss format
        return xml_builder.tag!("rdf:RDF",
            "xmlns" => FEED_TOOLS_NAMESPACES['rss10'],
            "xmlns:rdf" => FEED_TOOLS_NAMESPACES['rdf'],
            "xmlns:dc" => FEED_TOOLS_NAMESPACES['dc'],
            "xmlns:syn" => FEED_TOOLS_NAMESPACES['syn'],
            "xmlns:taxo" => FEED_TOOLS_NAMESPACES['taxo'],
            "xmlns:itunes" => FEED_TOOLS_NAMESPACES['itunes'],
            "xmlns:media" => FEED_TOOLS_NAMESPACES['media']) do
          channel_attributes = {}
          unless self.link.nil?
            channel_attributes["rdf:about"] =
              FeedTools.escape_entities(self.link)
          end
          xml_builder.channel(channel_attributes) do
            unless title.nil? || title == ""
              xml_builder.title(title)
            else
              xml_builder.title
            end
            unless link.nil? || link == ""
              xml_builder.link(link)
            else
              xml_builder.link
            end
            unless images.nil? || images.empty?
              xml_builder.image("rdf:resource" => FeedTools.escape_entities(
                images.first.url))
            end
            unless description.nil? || description == ""
              xml_builder.description(description)
            else
              xml_builder.description
            end
            unless language.nil? || language == ""
              xml_builder.tag!("dc:language", language)
            end
            xml_builder.tag!("syn:updatePeriod", "hourly")
            xml_builder.tag!("syn:updateFrequency",
              (time_to_live / 1.hour).to_s)
            xml_builder.tag!("syn:updateBase", Time.mktime(1970).iso8601)
            xml_builder.items do
              xml_builder.tag!("rdf:Seq") do
                unless items.nil?
                  for item in items
                    if item.link.nil?
                      raise "Cannot generate an rdf-based feed with a nil " +
                        "item link field."
                    end
                    xml_builder.tag!("rdf:li", "rdf:resource" =>
                      FeedTools.escape_entities(item.link))
                  end
                end
              end
            end
            build_xml_hook(feed_type, version, xml_builder)
          end
          unless images.nil? || images.empty?
            best_image = nil
            for image in self.images
              if image.link != nil
                best_image = image
                break
              end
            end
            best_image = images.first if best_image.nil?
            xml_builder.image(
                "rdf:about" => FeedTools.escape_entities(best_image.url)) do
              if !best_image.title.blank?
                xml_builder.title(best_image.title)
              elsif !self.title.blank?
                xml_builder.title(self.title)
              else
                xml_builder.title
              end
              unless best_image.url.blank?
                xml_builder.url(best_image.url)
              end
              if !best_image.link.blank?
                xml_builder.link(best_image.link)
              elsif !self.link.blank?
                xml_builder.link(self.link)
              else
                xml_builder.link
              end
            end
          end
          unless items.nil?
            for item in items
              item.build_xml(feed_type, version, xml_builder)
            end
          end
        end
      elsif feed_type == "rss"
        # normal rss format
        return xml_builder.rss("version" => "2.0",
            "xmlns:rdf" => FEED_TOOLS_NAMESPACES['rdf'],
            "xmlns:dc" => FEED_TOOLS_NAMESPACES['dc'],
            "xmlns:taxo" => FEED_TOOLS_NAMESPACES['taxo'],
            "xmlns:trackback" => FEED_TOOLS_NAMESPACES['trackback'],
            "xmlns:itunes" => FEED_TOOLS_NAMESPACES['itunes'],
            "xmlns:media" => FEED_TOOLS_NAMESPACES['media']) do
          xml_builder.channel do
            unless title.blank?
              xml_builder.title(title)
            end
            unless link.blank?
              xml_builder.link(link)
            end
            unless description.blank?
              xml_builder.description(description)
            end
            xml_builder.ttl((time_to_live / 1.minute).to_s)
            xml_builder.generator(
              FeedTools.configurations[:generator_href])
            build_xml_hook(feed_type, version, xml_builder)
            unless items.nil?
              for item in items
                item.build_xml(feed_type, version, xml_builder)
              end
            end
          end
        end
      elsif feed_type == "atom" && version == 0.3
        raise "Atom 0.3 is obsolete."
      elsif feed_type == "atom" && version == 1.0
        # normal atom format
        return xml_builder.feed("xmlns" => FEED_TOOLS_NAMESPACES['atom10'],
            "xml:lang" => language) do
          unless title.blank?
            xml_builder.title(title,
                "type" => "html")
          end
          xml_builder.author do
            unless self.author.nil? || self.author.name.nil?
              xml_builder.name(self.author.name)
            else
              xml_builder.name("n/a")
            end
            unless self.author.nil? || self.author.email.nil?
              xml_builder.email(self.author.email)
            end
            unless self.author.nil? || self.author.url.nil?
              xml_builder.uri(self.author.url)
            end
          end
          unless self.url.blank?
            xml_builder.link("href" => self.url,
                "rel" => "self",
                "type" => "application/atom+xml")
          end
          unless self.link.blank?
            xml_builder.link("href" => FeedTools.escape_entities(self.link),
                "rel" => "alternate",
                "type" => "text/html",
                "title" => FeedTools.escape_entities(self.title))
          end
          unless description.blank?
            xml_builder.subtitle(self.subtitle,
                "type" => "html")
          end
          if self.updated != nil
            xml_builder.updated(self.updated.iso8601)
          elsif self.time != nil
            # Not technically correct, but a heck of a lot better
            # than the Time.now fall-back.
            xml_builder.updated(self.time.iso8601)
          else
            xml_builder.updated(Time.now.gmtime.iso8601)
          end
          xml_builder.generator(FeedTools.configurations[:generator_name] +
            " - " + FeedTools.configurations[:generator_href])
          if self.id != nil
            unless FeedTools.is_uri? self.id
              if self.link != nil
                xml_builder.id(FeedTools.build_urn_uri(self.link))
              else
                raise "The unique id must be a valid URI."
              end
            else
              xml_builder.id(self.id)
            end
          elsif self.link != nil
            xml_builder.id(FeedTools.build_urn_uri(self.link))
          else
            raise "Cannot build feed, missing feed unique id."
          end
          build_xml_hook(feed_type, version, xml_builder)
          unless items.nil?
            for item in items
              item.build_xml(feed_type, version, xml_builder)
            end
          end
        end
      else
        raise "Unsupported feed format/version."
      end
    end

    # Persists the current feed state to the cache.
    def save
      unless self.url =~ /^file:\/\//
        if FeedTools.feed_cache.nil?
          raise "Caching is currently disabled.  Cannot save to cache."
        elsif self.url.nil?
          raise "The url field must be set to save to the cache."
        elsif self.cache_object.nil?
          raise "The cache_object is currently nil.  Cannot save to cache."
        else
          self.cache_object.url = self.url
          unless self.feed_data.nil?
            self.cache_object.title = self.title
            self.cache_object.link = self.link
            self.cache_object.feed_data = self.feed_data
            self.cache_object.feed_data_type = self.feed_data_type.to_s
          end
          self.cache_object.http_headers = self.http_headers.to_yaml
          self.cache_object.last_retrieved = self.last_retrieved
          self.cache_object.save
        end
      end
    end
  
    alias_method :tagline, :subtitle
    alias_method :tagline=, :subtitle=
    alias_method :description, :subtitle
    alias_method :description=, :subtitle=
    alias_method :abstract, :subtitle
    alias_method :abstract=, :subtitle=
    alias_method :content, :subtitle
    alias_method :content=, :subtitle=
    alias_method :ttl, :time_to_live
    alias_method :ttl=, :time_to_live=
    alias_method :guid, :id
    alias_method :guid=, :id=
    alias_method :items, :entries
    alias_method :items=, :entries=
  
    # passes missing methods to the cache_object
    def method_missing(msg, *params)
      if self.cache_object.nil?
        raise NoMethodError, "Invalid method #{msg.to_s}"
      end
      return self.cache_object.send(msg, params)
    end

    # passes missing methods to the FeedTools.feed_cache
    def Feed.method_missing(msg, *params)
      if FeedTools.feed_cache.nil?
        raise NoMethodError, "Invalid method Feed.#{msg.to_s}"
      end
      result = FeedTools.feed_cache.send(msg, params)
      if result.kind_of? FeedTools.feed_cache
        result = Feed.open(result.url)
      end
      return result
    end
  
    # Returns a simple representation of the feed object's state.
    def inspect
      return "#<FeedTools::Feed:0x#{self.object_id.to_s(16)} URL:#{self.url}>"
    end
  end
end