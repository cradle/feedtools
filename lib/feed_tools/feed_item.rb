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

module FeedTools
  # The <tt>FeedTools::FeedItem</tt> class represents the structure of
  # a single item within a web feed.
  class FeedItem
    # :stopdoc:
    include REXML
    include GenericHelper
    private :validate_options
    private :try_xpaths_all
    private :try_xpaths
    private :select_not_blank
    # :startdoc:
    
    # This class stores information about a feed item's file enclosures.
    class Enclosure
      # The url for the enclosure
      attr_accessor :url
      # The MIME type of the file referenced by the enclosure
      attr_accessor :type
      # The size of the file referenced by the enclosure
      attr_accessor :file_size
      # The total play time of the file referenced by the enclosure
      attr_accessor :duration
      # The height in pixels of the enclosed media
      attr_accessor :height
      # The width in pixels of the enclosed media
      attr_accessor :width
      # The bitrate of the enclosed media
      attr_accessor :bitrate
      # The framerate of the enclosed media
      attr_accessor :framerate
      # The thumbnail for this enclosure
      attr_accessor :thumbnail
      # The categories for this enclosure
      attr_accessor :categories
      # A hash of the enclosed file
      attr_accessor :hash
      # A website containing some kind of media player instead of a direct
      # link to the media file.
      attr_accessor :player
      # A list of credits for the enclosed media
      attr_accessor :credits
      # A text rendition of the enclosed media
      attr_accessor :text
      # A list of alternate version of the enclosed media file
      attr_accessor :versions
      # The default version of the enclosed media file
      attr_accessor :default_version
      
      # Returns true if this is the default enclosure
      def is_default?
        return @is_default
      end
      
      # Sets whether this is the default enclosure for the media group
      def is_default=(new_is_default)
        @is_default = new_is_default
      end
        
      # Returns true if the enclosure contains explicit material
      def explicit?
        return @explicit
      end
      
      # Sets the explicit attribute on the enclosure
      def explicit=(new_explicit)
        @explicit = new_explicit
      end
      
      # Determines if the object is a sample, or the full version of the
      # object, or if it is a stream.
      # Possible values are 'sample', 'full', 'nonstop'.
      def expression
        return @expression
      end
      
      # Sets the expression attribute on the enclosure.
      # Allowed values are 'sample', 'full', 'nonstop'.
      def expression=(new_expression)
        unless ['sample', 'full', 'nonstop'].include? new_expression.downcase
          raise ArgumentError,
            "Permitted values are 'sample', 'full', 'nonstop'."
        end
        @expression = new_expression.downcase
      end
      
      # Returns true if this enclosure contains audio content
      def audio?
        unless self.type.nil?
          return true if (self.type =~ /^audio/) != nil
        end
        # TODO: create a more complete list
        # =================================
        audio_extensions = ['mp3', 'm4a', 'm4p', 'wav', 'ogg', 'wma']
        audio_extensions.each do |extension|
          if (url =~ /#{extension}$/) != nil
            return true
          end
        end
        return false
      end

      # Returns true if this enclosure contains video content
      def video?
        unless self.type.nil?
          return true if (self.type =~ /^video/) != nil
          return true if self.type == "image/mov"
        end
        # TODO: create a more complete list
        # =================================
        video_extensions = ['mov', 'mp4', 'avi', 'wmv', 'asf']
        video_extensions.each do |extension|
          if (url =~ /#{extension}$/) != nil
            return true
          end
        end
        return false
      end
      
      alias_method :link, :url
      alias_method :link=, :url=
    end
    
    # TODO: Make these actual classes instead of structs
    # ==================================================
    EnclosureHash = Struct.new( "EnclosureHash", :hash, :type )
    EnclosurePlayer = Struct.new( "EnclosurePlayer", :url, :height, :width )
    EnclosureCredit = Struct.new( "EnclosureCredit", :name, :role )
    EnclosureThumbnail = Struct.new( "EnclosureThumbnail", :url, :height,
      :width )
    
    # Initialize the feed object
    def initialize
      super
      @feed_data = nil
      @feed_data_type = :xml
      @xml_doc = nil
      @root_node = nil
      @title = nil
      @id = nil
      @time = Time.now.gmtime
    end

    # Returns the parent feed of this feed item
    # Warning, this method may be slow if you have a
    # large number of FeedTools::Feed objects.  Can't
    # use a direct reference to the parent because it plays
    # havoc with the garbage collector.  Could've used
    # a WeakRef object, but really, if there are multiple
    # parent feeds, something is going to go wrong, and the
    # programmer needs to be notified.  A WeakRef
    # implementation can't detect this condition.
    def feed
      parent_feed = nil
      ObjectSpace.each_object(FeedTools::Feed) do |feed|
        if feed.instance_variable_get("@entries").nil?
          feed.items
        end
        unsorted_items = feed.instance_variable_get("@entries")
        for item in unsorted_items
          if item.object_id == self.object_id
            if parent_feed.nil?
              parent_feed = feed
              break
            else
              raise "Multiple parent feeds found."
            end
          end
        end
      end
      return parent_feed
    end
    
    # Returns the feed item's raw data.
    def feed_data
      return @feed_data
    end

    # Sets the feed item's data.
    def feed_data=(new_feed_data)
      @time = nil
      @feed_data = new_feed_data
    end

    # Returns the feed item's data type.
    def feed_data_type
      return @feed_data_type
    end

    # Sets the feed item's data type.
    def feed_data_type=(new_feed_data_type)
      @feed_data_type = new_feed_data_type
    end

    # Returns a REXML Document of the feed_data
    def xml
      if self.feed_data_type != :xml
        @xml_doc = nil
      else
        if @xml_doc.nil?
          # TODO: :ignore_whitespace_nodes => :all
          # Add that?
          # ======================================
          @xml_doc = Document.new(self.feed_data)
        end
      end
      return @xml_doc
    end

    # Returns the first node within the root_node that matches the xpath query.
    def find_node(xpath, select_result_value=false)
      if feed.feed_data_type != :xml
        raise "The feed data type is not xml."
      end
      return try_xpaths(self.root_node, [xpath],
        :select_result_value => select_result_value)
    end

    # Returns all nodes within the root_node that match the xpath query.
    def find_all_nodes(xpath, select_result_value=false)
      if feed.feed_data_type != :xml
        raise "The feed data type is not xml."
      end
      return try_xpaths_all(self.root_node, [xpath],
        :select_result_value => select_result_value)
    end

    # Returns the root node of the feed item.
    def root_node
      if @root_node.nil?
        if xml.nil?
          return nil
        end
        @root_node = xml.root
      end
      return @root_node
    end

    # Returns the feed items's unique id
    def id
      if @id.nil?
        @id = try_xpaths(self.root_node, [
          "atom10:id/text()",
          "atom03:id/text()",
          "atom:id/text()",
          "id/text()",
          "guid/text()"
        ], :select_result_value => true)
      end
      return @id
    end

    # Sets the feed item's unique id
    def id=(new_id)
      @id = new_id
    end

    # Returns the feed item title
    def title
      if @title.nil?
        repair_entities = false
        title_node = try_xpaths(self.root_node, [
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
        if !@title.blank? && FeedTools.configurations[:strip_comment_count]
          # Some blogging tools include the number of comments in a post
          # in the title... this is supremely ugly, and breaks any
          # applications which expect the title to be static, so we're
          # gonna strip them out.
          #
          # If for some incredibly wierd reason you need the actual
          # unstripped title, just use find_node("title/text()").to_s
          @title = @title.strip.gsub(/\[\d*\]$/, "").strip
        end
        @title.gsub!(/>\n</, "><")
        @title.gsub!(/\n/, " ")
        @title.strip!
        @title = nil if @title.blank?
      end
      return @title
    end
    
    # Sets the feed item title
    def title=(new_title)
      @title = new_title
    end

    # Returns the feed item content
    def content
      if @content.nil?
        repair_entities = false
        content_node = try_xpaths(self.root_node, [
          "atom10:content",
          "atom03:content",
          "atom:content",
          "content:encoded",
          "content",
          "fullitem",
          "xhtml:body",
          "body",
          "encoded",
          "description",
          "tagline",
          "subtitle",
          "atom10:summary",
          "atom03:summary",
          "atom:summary",
          "summary",
          "abstract",
          "blurb",
          "info"
        ])
        if content_node.nil?
          return nil
        end
        content_type = try_xpaths(content_node, "@type",
          :select_result_value => true)
        content_mode = try_xpaths(content_node, "@mode",
          :select_result_value => true)
        content_encoding = try_xpaths(content_node, "@encoding",
          :select_result_value => true)

        # Note that we're checking for misuse of type, mode and encoding here
        if !content_encoding.blank?
          @content =
            "[Embedded data objects are not currently supported.]"
        elsif content_node.cdatas.size > 0
          @content = content_node.cdatas.first.value
        elsif content_type == "base64" || content_mode == "base64" ||
            content_encoding == "base64"
          @content = Base64.decode64(content_node.inner_xml.strip)
        elsif content_type == "xhtml" || content_mode == "xhtml" ||
            content_type == "xml" || content_mode == "xml" ||
            content_type == "application/xhtml+xml"
          @content = content_node.inner_xml
        elsif content_type == "escaped" || content_mode == "escaped"
          @content = FeedTools.unescape_entities(
            content_node.inner_xml)
        else
          @content = content_node.inner_xml
          repair_entities = true
        end
        if @content.blank?
          @content = self.itunes_summary
        end
        if @content.blank?
          @content = self.itunes_subtitle
        end

        unless @content.blank?
          @content = FeedTools.sanitize_html(@content, :strip)
          @content = FeedTools.unescape_entities(@content) if repair_entities
          @content = FeedTools.tidy_html(@content)
        end

        @content = @content.strip unless @content.nil?
        @content = nil if @content.blank?
      end
      return @content
    end

    # Sets the feed item content
    def content=(new_content)
      @content = new_content
    end

    # Returns the feed item summary
    def summary
      if @summary.nil?
        repair_entities = false
        summary_node = try_xpaths(self.root_node, [
          "atom10:summary",
          "atom03:summary",
          "atom:summary",
          "summary",
          "abstract",
          "blurb",
          "description",
          "tagline",
          "subtitle",
          "fullitem",
          "xhtml:body",
          "body",
          "content:encoded",
          "encoded",
          "atom10:content",
          "atom03:content",
          "atom:content",
          "content",
          "info"
        ])
        if summary_node.nil?
          return nil
        end
        summary_type = try_xpaths(summary_node, "@type",
          :select_result_value => true)
        summary_mode = try_xpaths(summary_node, "@mode",
          :select_result_value => true)
        summary_encoding = try_xpaths(summary_node, "@encoding",
          :select_result_value => true)

        # Note that we're checking for misuse of type, mode and encoding here
        if !summary_encoding.blank?
          @summary =
            "[Embedded data objects are not currently supported.]"
        elsif summary_node.cdatas.size > 0
          @summary = summary_node.cdatas.first.value
        elsif summary_type == "base64" || summary_mode == "base64" ||
            summary_encoding == "base64"
          @summary = Base64.decode64(summary_node.inner_xml.strip)
        elsif summary_type == "xhtml" || summary_mode == "xhtml" ||
            summary_type == "xml" || summary_mode == "xml" ||
            summary_type == "application/xhtml+xml"
          @summary = summary_node.inner_xml
        elsif summary_type == "escaped" || summary_mode == "escaped"
          @summary = FeedTools.unescape_entities(
            summary_node.inner_xml)
        else
          @summary = summary_node.inner_xml
          repair_entities = true
        end
        if @summary.blank?
          @summary = self.itunes_summary
        end
        if @summary.blank?
          @summary = self.itunes_subtitle
        end

        unless @summary.blank?
          @summary = FeedTools.sanitize_html(@summary, :strip)
          @summary = FeedTools.unescape_entities(@summary) if repair_entities
          @summary = FeedTools.tidy_html(@summary)
        end

        @summary = @summary.strip unless @summary.nil?
        @summary = nil if @summary.blank?
      end
      return @summary
    end

    # Sets the feed item summary
    def summary=(new_summary)
      @summary = new_summary
    end
    
    # Returns the contents of the itunes:summary element
    def itunes_summary
      if @itunes_summary.nil?
        @itunes_summary = try_xpaths(self.root_node, [
          "itunes:summary/text()"
        ], :select_result_value => true)
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
        @itunes_subtitle = try_xpaths(self.root_node, [
          "itunes:subtitle/text()"
        ], :select_result_value => true)
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

    # Returns the contents of the media:text element
    def media_text
      if @media_text.nil?
        @media_text = FeedTools.unescape_entities(XPath.first(root_node,
          "itunes:subtitle/text()").to_s)
        if @media_text == ""
          @media_text = nil
        end
        unless @media_text.nil?
          @media_text = FeedTools.sanitize_html(@media_text)
        end
      end
      return @media_text
    end

    # Sets the contents of the media:text element
    def media_text=(new_media_text)
      @media_text = new_media_text
    end

    # Returns the feed item link
    def link
      if @link.nil?
        @link = try_xpaths(self.root_node, [
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
          "@rdf:about",
          "guid[@isPermaLink='true']/text()",
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
        if !@link.blank?
          @link = FeedTools.unescape_entities(@link)
        end
# TODO: Actually implement proper relative url resolving instead of this crap
# ===========================================================================
# 
#        if @link != "" && (@link =~ /http:\/\//) != 0 && (@link =~ /https:\/\//) != 0
#          if (feed.base[-1..-1] == "/" && @link[0..0] == "/")
#            @link = @link[1..-1]
#          end
#          # prepend the base to the link since they seem to have used a relative path
#          @link = feed.base + @link
#        end
        if @link.blank?
          link_node = try_xpaths(self.root_node, [
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
              for child in self.root_node
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
        @link = self.comments if @link.blank?
        @link = nil if @link.blank?
        if FeedTools.configurations[:url_normalization_enabled]
          @link = FeedTools.normalize_url(@link)
        end
      end
      return @link
    end
    
    # Sets the feed item link
    def link=(new_link)
      @link = new_link
    end
        
    # Returns a list of the feed item's categories
    def categories
      if @categories.nil?
        @categories = []
        category_nodes = try_xpaths_all(self.root_node, [
          "category",
          "dc:subject"
        ])
        for category_node in category_nodes
          category = FeedTools::Feed::Category.new
          category.term = try_xpaths(category_node, ["@term", "text()"],
            :select_result_value => true)
          category.term.strip! unless category.term.nil?
          category.label = try_xpaths(category_node, ["@label"],
            :select_result_value => true)
          category.label.strip! unless category.label.nil?
          category.scheme = try_xpaths(category_node, [
            "@scheme",
            "@domain"
          ], :select_result_value => true)
          category.scheme.strip! unless category.scheme.nil?
          @categories << category
        end
      end
      return @categories
    end
    
    # Returns a list of the feed items's images
    def images
      if @images.nil?
        @images = []
        image_nodes = try_xpaths_all(self.root_node, [
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
    
    # Returns the feed item itunes image link
    def itunes_image_link
      if @itunes_image_link.nil?
        @itunes_image_link = try_xpaths(self.root_node, [
          "itunes:image/@href",
          "itunes:link[@rel='image']/@href"
        ], :select_result_value => true)
        if FeedTools.configurations[:url_normalization_enabled]
          @itunes_image_link = FeedTools.normalize_url(@itunes_image_link)
        end
      end
      return @itunes_image_link
    end

    # Sets the feed item itunes image link
    def itunes_image_link=(new_itunes_image_link)
      @itunes_image_link = new_itunes_image_link
    end
    
    # Returns the feed item media thumbnail link
    def media_thumbnail_link
      if @media_thumbnail_link.nil?
        @media_thumbnail_link = try_xpaths(self.root_node, [
          "media:thumbnail/@url"
        ], :select_result_value => true)
        if FeedTools.configurations[:url_normalization_enabled]
          @media_thumbnail_link = FeedTools.normalize_url(@media_thumbnail_link)
        end
      end
      return @media_thumbnail_link
    end

    # Sets the feed item media thumbnail url
    def media_thumbnail_link=(new_media_thumbnail_link)
      @media_thumbnail_link = new_media_thumbnail_link
    end

    # Returns the feed item's copyright information
    def copyright
      if @copyright.nil?
        repair_entities = false
        copyright_node = try_xpaths(self.root_node, [
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

    # Sets the feed item's copyright information
    def copyright=(new_copyright)
      @copyright = new_copyright
    end

    # Returns all feed item enclosures
    def enclosures
      if @enclosures.nil?
        @enclosures = []
        
        # First, load up all the different possible sources of enclosures
        rss_enclosures =
          try_xpaths_all(self.root_node, ["enclosure"])
        atom_enclosures =
          try_xpaths_all(self.root_node, [
            "atom10:link[@rel='enclosure']",
            "atom03:link[@rel='enclosure']",
            "atom:link[@rel='enclosure']",
            "link[@rel='enclosure']"
          ])
        media_content_enclosures =
          try_xpaths_all(self.root_node, ["media:content"])
        media_group_enclosures =
          try_xpaths_all(self.root_node, ["media:group"])

        # Parse RSS-type enclosures.  Thanks to a few buggy enclosures
        # implementations, sometimes these also manage to show up in atom
        # files.
        for enclosure_node in rss_enclosures
          enclosure = Enclosure.new
          enclosure.url = FeedTools.unescape_entities(
            enclosure_node.attributes["url"].to_s)
          enclosure.type = enclosure_node.attributes["type"].to_s
          enclosure.file_size = enclosure_node.attributes["length"].to_i
          enclosure.credits = []
          enclosure.explicit = false
          @enclosures << enclosure
        end
        
        # Parse atom-type enclosures.  If there are repeats of the same
        # enclosure object, we merge the two together.
        for enclosure_node in atom_enclosures
          enclosure_url = FeedTools.unescape_entities(
            enclosure_node.attributes["href"].to_s)
          enclosure = nil
          new_enclosure = false
          for existing_enclosure in @enclosures
            if existing_enclosure.url == enclosure_url
              enclosure = existing_enclosure
              break
            end
          end
          if enclosure.nil?
            new_enclosure = true
            enclosure = Enclosure.new
          end
          enclosure.url = enclosure_url
          enclosure.type = enclosure_node.attributes["type"].to_s
          enclosure.file_size = enclosure_node.attributes["length"].to_i
          enclosure.credits = []
          enclosure.explicit = false
          if new_enclosure
            @enclosures << enclosure
          end
        end

        # Creates an anonymous method to parse content objects from the media
        # module.  We do this to avoid excessive duplication of code since we
        # have to do identical processing for content objects within group
        # objects.
        parse_media_content = lambda do |media_content_nodes|
          affected_enclosures = []
          for enclosure_node in media_content_nodes
            enclosure_url = FeedTools.unescape_entities(
              enclosure_node.attributes["url"].to_s)
            enclosure = nil
            new_enclosure = false
            for existing_enclosure in @enclosures
              if existing_enclosure.url == enclosure_url
                enclosure = existing_enclosure
                break
              end
            end
            if enclosure.nil?
              new_enclosure = true
              enclosure = Enclosure.new
            end
            enclosure.url = enclosure_url
            enclosure.type = enclosure_node.attributes["type"].to_s
            enclosure.file_size = enclosure_node.attributes["fileSize"].to_i
            enclosure.duration = enclosure_node.attributes["duration"].to_s
            enclosure.height = enclosure_node.attributes["height"].to_i
            enclosure.width = enclosure_node.attributes["width"].to_i
            enclosure.bitrate = enclosure_node.attributes["bitrate"].to_i
            enclosure.framerate = enclosure_node.attributes["framerate"].to_i
            enclosure.expression =
              enclosure_node.attributes["expression"].to_s
            enclosure.is_default =
              (enclosure_node.attributes["isDefault"].to_s.downcase == "true")
            enclosure_thumbnail_url = try_xpaths(enclosure_node,
              ["media:thumbnail/@url"], :select_result_value => true)
            if !enclosure_thumbnail_url.blank?
              enclosure.thumbnail = EnclosureThumbnail.new(
                FeedTools.unescape_entities(enclosure_thumbnail_url),
                FeedTools.unescape_entities(
                  try_xpaths(enclosure_node, ["media:thumbnail/@height"],
                    :select_result_value => true)),
                FeedTools.unescape_entities(
                  try_xpaths(enclosure_node, ["media:thumbnail/@width"],
                    :select_result_value => true))
              )
            end
            enclosure.categories = []
            for category in try_xpaths_all(enclosure_node, ["media:category"])
              enclosure.categories << FeedTools::Feed::Category.new
              enclosure.categories.last.term =
                FeedTools.unescape_entities(category.inner_xml)
              enclosure.categories.last.scheme =
                FeedTools.unescape_entities(
                  category.attributes["scheme"].to_s)
              enclosure.categories.last.label =
                FeedTools.unescape_entities(
                  category.attributes["label"].to_s)
              if enclosure.categories.last.scheme.blank?
                enclosure.categories.last.scheme = nil
              end
              if enclosure.categories.last.label.blank?
                enclosure.categories.last.label = nil
              end
            end
            enclosure_media_hash = try_xpaths(enclosure_node,
              ["media:hash/text()"], :select_result_value => true)
            if !enclosure_media_hash.nil?
              enclosure.hash = EnclosureHash.new(
                FeedTools.sanitize_html(FeedTools.unescape_entities(
                  enclosure_media_hash), :strip),
                "md5"
              )
            end
            enclosure_media_player_url = try_xpaths(enclosure_node,
              ["media:player/@url"], :select_result_value => true)
            if !enclosure_media_player_url.blank?
              enclosure.player = EnclosurePlayer.new(
                FeedTools.unescape_entities(enclosure_media_player_url),
                FeedTools.unescape_entities(
                  try_xpaths(enclosure_node,
                    ["media:player/@height"], :select_result_value => true)),
                FeedTools.unescape_entities(
                  try_xpaths(enclosure_node,
                    ["media:player/@width"], :select_result_value => true))
              )
            end
            enclosure.credits = []
            for credit in try_xpaths_all(enclosure_node, ["media:credit"])
              enclosure.credits << EnclosureCredit.new(
                FeedTools.unescape_entities(credit.inner_xml.to_s.strip),
                FeedTools.unescape_entities(
                  credit.attributes["role"].to_s.downcase)
              )
              if enclosure.credits.last.name.blank?
                enclosure.credits.last.name = nil
              end
              if enclosure.credits.last.role.blank?
                enclosure.credits.last.role = nil
              end
            end
            enclosure.explicit = (try_xpaths(enclosure_node,
              ["media:adult/text()"]).to_s.downcase == "true")
            enclosure_media_text =
              try_xpaths(enclosure_node, ["media:text/text()"])
            if !enclosure_media_text.blank?
              enclosure.text = FeedTools.unescape_entities(
                enclosure_media_text)
            end
            affected_enclosures << enclosure
            if new_enclosure
              @enclosures << enclosure
            end
          end
          affected_enclosures
        end
        
        # Parse the independant content objects.
        parse_media_content.call(media_content_enclosures)
        
        media_groups = []
        
        # Parse the group objects.
        for media_group in media_group_enclosures
          group_media_content_enclosures =
            try_xpaths_all(media_group, ["media:content"])
          
          # Parse the content objects within the group objects.
          affected_enclosures =
            parse_media_content.call(group_media_content_enclosures)
          
          # Now make sure that content objects inherit certain properties from
          # the group objects.
          for enclosure in affected_enclosures
            media_group_thumbnail = try_xpaths(media_group,
              ["media:thumbnail/@url"], :select_result_value => true)
            if enclosure.thumbnail.nil? && !media_group_thumbnail.blank?
              enclosure.thumbnail = EnclosureThumbnail.new(
                FeedTools.unescape_entities(
                  media_group_thumbnail),
                FeedTools.unescape_entities(
                  try_xpaths(media_group, ["media:thumbnail/@height"],
                    :select_result_value => true)),
                FeedTools.unescape_entities(
                  try_xpaths(media_group, ["media:thumbnail/@width"],
                    :select_result_value => true))
              )
            end
            if (enclosure.categories.blank?)
              enclosure.categories = []
              for category in try_xpaths_all(media_group, ["media:category"])
                enclosure.categories << FeedTools::Feed::Category.new
                enclosure.categories.last.term =
                  FeedTools.unescape_entities(category.inner_xml)
                enclosure.categories.last.scheme =
                  FeedTools.unescape_entities(
                    category.attributes["scheme"].to_s)
                enclosure.categories.last.label =
                  FeedTools.unescape_entities(
                    category.attributes["label"].to_s)
                if enclosure.categories.last.scheme.blank?
                  enclosure.categories.last.scheme = nil
                end
                if enclosure.categories.last.label.blank?
                  enclosure.categories.last.label = nil
                end
              end
            end
            enclosure_media_group_hash = try_xpaths(enclosure_node,
              ["media:hash/text()"], :select_result_value => true)
            if enclosure.hash.nil? && !enclosure_media_group_hash.blank?
              enclosure.hash = EnclosureHash.new(
                FeedTools.sanitize_html(FeedTools.unescape_entities(
                  enclosure_media_group_hash), :strip),
                "md5"
              )
            end
            enclosure_media_group_url = try_xpaths(media_group,
              "media:player/@url", :select_result_value => true)
            if enclosure.player.nil? && !enclosure_media_group_url.blank?
              enclosure.player = EnclosurePlayer.new(
                FeedTools.unescape_entities(enclosure_media_group_url),
                FeedTools.unescape_entities(
                  try_xpaths(media_group, ["media:player/@height"],
                    :select_result_value => true)),
                FeedTools.unescape_entities(
                  try_xpaths(media_group, ["media:player/@width"],
                    :select_result_value => true))
              )
            end
            if enclosure.credits.nil? || enclosure.credits.size == 0
              enclosure.credits = []
              for credit in try_xpaths_all(media_group, ["media:credit"])
                enclosure.credits << EnclosureCredit.new(
                  FeedTools.unescape_entities(credit.inner_xml),
                  FeedTools.unescape_entities(
                    credit.attributes["role"].to_s.downcase)
                )
                if enclosure.credits.last.role.blank?
                  enclosure.credits.last.role = nil
                end
              end
            end
            if enclosure.explicit?.nil?
              enclosure.explicit = ((try_xpaths(media_group, [
                "media:adult/text()"
              ], :select_result_value => true).downcase == "true") ?
                true : false)
            end
            enclosure_media_group_text = try_xpaths(media_group,
              ["media:text/text()"], :select_result_value => true)
            if enclosure.text.nil? && !enclosure_media_group_text.blank?
              enclosure.text = FeedTools.sanitize_html(
                FeedTools.unescape_entities(
                  enclosure_media_group_text), :strip)
            end
          end
          
          # Keep track of the media groups
          media_groups << affected_enclosures
        end
        
        # Now we need to inherit any relevant item level information.
        if self.explicit?
          for enclosure in @enclosures
            enclosure.explicit = true
          end
        end
        
        # Add all the itunes categories
        itunes_categories =
          try_xpaths_all(self.root_node, ["itunes:category"])
        for itunes_category in itunes_categories
          genre = "Podcasts"
          category = itunes_category.attributes["text"].to_s
          subcategory =
            try_xpaths(itunes_category, ["itunes:category/@text"],
              :select_result_value => true)
          category_path = genre
          if !category.blank?
            category_path << "/" + category
          end
          if !subcategory.blank?
            category_path << "/" + subcategory
          end          
          for enclosure in @enclosures
            if enclosure.categories.nil?
              enclosure.categories = []
            end
            enclosure.categories << FeedTools::Feed::Category.new
            enclosure.categories.last.term =
              FeedTools.unescape_entities(category_path)
            enclosure.categories.last.scheme =
              "http://www.apple.com/itunes/store/"
            enclosure.categories.last.label =
              "iTunes Music Store Categories"
          end
        end

        for enclosure in @enclosures
          # Clean up any of those attributes that incorrectly have ""
          # or 0 as their values        
          if enclosure.type.blank?
            enclosure.type = nil
          end
          if enclosure.file_size == 0
            enclosure.file_size = nil
          end
          if enclosure.duration == 0
            enclosure.duration = nil
          end
          if enclosure.height == 0
            enclosure.height = nil
          end
          if enclosure.width == 0
            enclosure.width = nil
          end
          if enclosure.bitrate == 0
            enclosure.bitrate = nil
          end
          if enclosure.framerate == 0
            enclosure.framerate = nil
          end
          if enclosure.expression.blank?
            enclosure.expression = "full"
          end

          # If an enclosure is missing the text field, fall back on the
          # itunes:summary field
          if enclosure.text.blank?
            enclosure.text = self.itunes_summary
          end

          # Make sure we don't have duplicate categories
          unless enclosure.categories.nil?
            enclosure.categories.uniq!
          end
        end
        
        # And finally, now things get complicated.  This is where we make
        # sure that the enclosures method only returns either default
        # enclosures or enclosures with only one version.  Any enclosures
        # that are wrapped in a media:group will be placed in the appropriate
        # versions field.
        affected_enclosure_urls = []
        for media_group in media_groups
          affected_enclosure_urls =
            affected_enclosure_urls | (media_group.map do |enclosure|
              enclosure.url
            end)
        end
        @enclosures.delete_if do |enclosure|
          (affected_enclosure_urls.include? enclosure.url)
        end
        for media_group in media_groups
          default_enclosure = nil
          for enclosure in media_group
            if enclosure.is_default?
              default_enclosure = enclosure
            end
          end
          for enclosure in media_group
            enclosure.default_version = default_enclosure
            enclosure.versions = media_group.clone
            enclosure.versions.delete(enclosure)
          end
          @enclosures << default_enclosure
        end
      end

      # If we have a single enclosure, it's safe to inherit the
      # itunes:duration field if it's missing.
      if @enclosures.size == 1
        if @enclosures.first.duration.nil? || @enclosures.first.duration == 0
          @enclosures.first.duration = self.itunes_duration
        end
      end

      return @enclosures
    end
    
    def enclosures=(new_enclosures)
      @enclosures = new_enclosures
    end
    
    # Returns the feed item author
    def author
      if @author.nil?
        @author = FeedTools::Feed::Author.new
        author_node = try_xpaths(self.root_node, [
          "atom10:author",
          "atom03:author",
          "atom:author",
          "author",
          "managingEditor",
          "dc:author",
          "dc:creator",
          "creator"
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
              unless raw_scan.size == 0
                author_raw_pair = raw_scan.first.reverse
              end
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
                # that the creator didn't intend to contain an email address
                # if it got through the preceeding regexes and it doesn't
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
    
    # Sets the feed item author
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

        # Set the author name
        @publisher.raw = FeedTools.unescape_entities(
          try_xpaths(self.root_node, [
            "dc:publisher/text()",
            "webMaster/text()"
          ], :select_result_value => true))
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
    # This inherits from any incorrectly placed channel-level itunes:author
    # elements.  They're actually amazingly common.  People don't read specs.
    def itunes_author
      if @itunes_author.nil?
        @itunes_author = FeedTools.unescape_entities(
          try_xpaths(self.root_node,
            ["itunes:author/text()"], :select_result_value => true))
        @itunes_author = feed.itunes_author if @itunes_author.blank?
      end
      return @itunes_author
    end

    # Sets the contents of the itunes:author element
    def itunes_author=(new_itunes_author)
      @itunes_author = new_itunes_author
    end        
        
    # Returns the number of seconds that the associated media runs for
    def itunes_duration
      if @itunes_duration.nil?
        raw_duration = FeedTools.unescape_entities(
          try_xpaths(self.root_node,
            ["itunes:duration/text()"], :select_result_value => true))
        if !raw_duration.blank?
          hms = raw_duration.split(":").map { |x| x.to_i }
          if hms.size == 3
            @itunes_duration = hms[0].hours + hms[1].minutes + hms[2]
          elsif hms.size == 2
            @itunes_duration = hms[0].minutes + hms[1]
          elsif hms.size == 1
            @itunes_duration = hms[0]
          end
        end
      end
      return @itunes_duration
    end
    
    # Sets the number of seconds that the associate media runs for
    def itunes_duration=(new_itunes_duration)
      @itunes_duration = new_itunes_duration
    end
    
    # Returns the feed item time
    def time(options = {})
      validate_options([ :estimate_timestamp ],
                       options.keys)
      options = { :estimate_timestamp => true }.merge(options)
      if @time.nil?
        time_string = try_xpaths(self.root_node, [
          "atom10:updated/text()",
          "atom03:updated/text()",
          "atom:updated/text()",
          "updated/text()",
          "atom10:modified/text()",
          "atom03:modified/text()",
          "atom:modified/text()",
          "modified/text()",
          "time/text()",
          "lastBuildDate/text()",
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
          if !time_string.blank?
            @time = Time.parse(time_string).gmtime
          elsif FeedTools.configurations[:timestamp_estimation_enabled] &&
              !self.title.nil? &&
              (Time.parse(self.title) - Time.now).abs > 100
            @time = Time.parse(self.title).gmtime
          end
        rescue
        end
        if FeedTools.configurations[:timestamp_estimation_enabled]
          if options[:estimate_timestamp]
            if @time.nil?
              begin
                @time = succ_time
                if @time.nil?
                  @time = prev_time
                end
              rescue
              end
              if @time.nil?
                @time = Time.now.gmtime
              end
            end
          end
        end
      end
      return @time
    end
    
    # Sets the feed item time
    def time=(new_time)
      @time = new_time
    end
    
    # Returns 1 second after the previous item's time.
    def succ_time #:nodoc:
      begin
        parent_feed = self.feed
        if parent_feed.nil?
          return nil
        end
        if parent_feed.instance_variable_get("@entries").nil?
          parent_feed.items
        end
        unsorted_items = parent_feed.instance_variable_get("@entries")
        item_index = unsorted_items.index(self)
        if item_index.nil?
          return nil
        end
        if item_index <= 0
          return nil
        end
        previous_item = unsorted_items[item_index - 1]
        return (previous_item.time(:estimate_timestamp => false) + 1)
      rescue
        return nil
      end
    end
    private :succ_time

    # Returns 1 second before the succeeding item's time.
    def prev_time #:nodoc:
      begin
        parent_feed = self.feed
        if parent_feed.nil?
          return nil
        end
        if parent_feed.instance_variable_get("@entries").nil?
          parent_feed.items
        end
        unsorted_items = parent_feed.instance_variable_get("@entries")
        item_index = unsorted_items.index(self)
        if item_index.nil?
          return nil
        end
        if item_index >= (unsorted_items.size - 1)
          return nil
        end
        succeeding_item = unsorted_items[item_index + 1]
        return (succeeding_item.time(:estimate_timestamp => false) - 1)
      rescue
        return nil
      end
    end
    private :prev_time
    
    # Returns the feed item updated time
    def updated
      if @updated.nil?
        updated_string = try_xpaths(self.root_node, [
          "atom10:updated/text()",
          "atom03:updated/text()",
          "atom:updated/text()",
          "updated/text()",
          "atom10:modified/text()",
          "atom03:modified/text()",
          "atom:modified/text()",
          "modified/text()",
          "lastBuildDate/text()"
        ], :select_result_value => true)
        if !updated_string.blank?
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
        published_string = try_xpaths(self.root_node, [
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
        if !published_string.blank?
          @issued = Time.parse(published_string).gmtime rescue nil
        else
          @issued = nil
        end
      end
      return @issued
    end
    
    # Sets the feed item published time
    def published=(new_published)
      @published = new_published
    end
        
    # Returns the url for posting comments
    def comments
      if @comments.nil?
        @comments = try_xpaths(self.root_node, ["comments/text()"],
          :select_result_value => true)
        if FeedTools.configurations[:url_normalization_enabled]
          @comments = FeedTools.normalize_url(@comments)
        end
      end
      return @comments
    end
    
    # Sets the url for posting comments
    def comments=(new_comments)
      @comments = new_comments
    end
    
    # The source that this post was based on
    def source
      if @source.nil?
        @source = FeedTools::Feed::Link.new
        @source.url = try_xpaths(self.root_node, ["source/@url"],
          :select_result_value => true)
        @source.value = try_xpaths(self.root_node, ["source/text()"],
          :select_result_value => true)
      end
      return @source
    end
        
    # Returns the feed item tags
    def tags
      # TODO: support the rel="tag" microformat
      # =======================================
      if @tags.nil?
        @tags = []
        if root_node.nil?
          return @tags
        end
        if @tags.nil? || @tags.size == 0
          @tags = []
          tag_list = try_xpaths_all(self.root_node,
            ["dc:subject/rdf:Bag/rdf:li/text()"],
            :select_result_value => true)
          if tag_list != nil && tag_list.size > 0
            for tag in tag_list
              @tags << tag.downcase.strip
            end
          end
        end
        if @tags.nil? || @tags.size == 0
          # messy effort to find ourselves some tags, mainly for del.icio.us
          @tags = []
          rdf_bag = try_xpaths_all(self.root_node,
            ["taxo:topics/rdf:Bag/rdf:li"])
          if rdf_bag != nil && rdf_bag.size > 0
            for tag_node in rdf_bag
              begin
                tag_url = try_xpaths(tag_node, ["@resource"],
                  :select_result_value => true)
                tag_match = tag_url.scan(/\/(tag|tags)\/(\w+)$/)
                if tag_match.size > 0
                  @tags << tag_match.first.last.downcase.strip
                end
              rescue
              end
            end
          end
        end
        if @tags.nil? || @tags.size == 0
          @tags = []
          tag_list = try_xpaths_all(self.root_node, ["category/text()"],
            :select_result_value => true)
          for tag in tag_list
            @tags << tag.to_s.downcase.strip
          end
        end
        if @tags.nil? || @tags.size == 0
          @tags = []
          tag_list = try_xpaths_all(self.root_node, ["dc:subject/text()"],
            :select_result_value => true)
          for tag in tag_list
            @tags << tag.to_s.downcase.strip
          end
        end
        if @tags.blank?
          begin
            itunes_keywords_string = try_xpaths(self.root_node, [
              "itunes:keywords/text()"
            ], :select_result_value => true)
            unless itunes_keywords_string.blank?
              @tags = itunes_keywords_string.downcase.split(",")
              if @tags.size == 1
                @tags = itunes_keywords_string.downcase.split(" ")
                @tags = @tags.map { |tag| tag.chomp(",") }
              end
              if @tags.size == 1
                @tags = itunes_keywords_string.downcase.split(",")
              end
              @tags = @tags.map { |tag| tag.strip }
            end
          rescue
            @tags = []
          end
        end
        if @tags.nil?
          @tags = []
        end
        @tags.uniq!
      end
      return @tags
    end
    
    # Sets the feed item tags
    def tags=(new_tags)
      @tags = new_tags
    end
    
    # Returns true if this feed item contains explicit material.  If the whole
    # feed has been marked as explicit, this will return true even if the item
    # isn't explicitly marked as explicit.
    def explicit?
      if @explicit.nil?
        explicit_string = try_xpaths(self.root_node, [
          "media:adult/text()",
          "itunes:explicit/text()"
        ], :select_result_value => true)
        if explicit_string == "true" || explicit_string == "yes" ||
            feed.explicit?
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
    
    # A hook method that is called during the feed generation process.  Overriding this method
    # will enable additional content to be inserted into the feed.
    def build_xml_hook(feed_type, version, xml_builder)
      return nil
    end

    # Generates xml based on the content of the feed item
    def build_xml(feed_type=(self.feed.feed_type or "atom"), version=nil,
        xml_builder=Builder::XmlMarkup.new(
          :indent => 2, :escape_attrs => false))
      if feed_type == "rss" && (version == nil || version == 0.0)
        version = 1.0
      elsif feed_type == "atom" && (version == nil || version == 0.0)
        version = 1.0
      end
      if feed_type == "rss" && (version == 0.9 || version == 1.0 || version == 1.1)
        # RDF-based rss format
        if link.nil?
          raise "Cannot generate an rdf-based feed item with a nil link field."
        end
        return xml_builder.item("rdf:about" =>
            FeedTools.escape_entities(link)) do
          unless title.blank?
            xml_builder.title(title)
          else
            xml_builder.title
          end
          unless link.blank?
            xml_builder.link(link)
          else
            xml_builder.link
          end
          unless self.summary.blank?
            xml_builder.description(self.summary)
          else
            xml_builder.description
          end
          unless self.content.blank?
            xml_builder.tag!("content:encoded") do
              xml_builder.cdata!(self.content)
            end
          end
          unless time.nil?
            xml_builder.tag!("dc:date", time.iso8601)            
          end
          unless tags.nil? || tags.size == 0
#             for tag in tags
#               xml_builder.tag!("category", tag)
#             end
            xml_builder.tag!("dc:subject") do
              xml_builder.tag!("rdf:Bag") do
                for tag in tags
                  xml_builder.tag!("rdf:li", tag)
                end
              end
            end
            if self.feed.podcast?
              xml_builder.tag!("itunes:keywords", tags.join(", "))
            end
          end
          build_xml_hook(feed_type, version, xml_builder)
        end
      elsif feed_type == "rss"
        # normal rss format
        return xml_builder.item do
          unless self.title.blank?
            xml_builder.title(self.title)
          end
          unless self.link.blank?
            xml_builder.link(link)
          end
          unless self.summary.blank?
            xml_builder.description(self.summary)
          end
          unless self.content.blank?
            xml_builder.tag!("content:encoded") do
              xml_builder.cdata!(self.content)
            end
          end
          if !self.published.nil?
            xml_builder.pubDate(self.published.rfc822)            
          elsif !self.time.nil?
            xml_builder.pubDate(self.time.rfc822)            
          end
          unless self.guid.blank?
            if FeedTools.is_uri?(self.guid) && (self.guid =~ /^http/)
              xml_builder.guid(self.guid, "isPermaLink" => "true")
            else
              xml_builder.guid(self.guid, "isPermaLink" => "false")
            end
          else
            unless self.link.blank?
              xml_builder.guid(self.link, "isPermaLink" => "true")
            end
          end
          unless tags.nil? || tags.size == 0
#             for tag in tags
#               xml_builder.tag!("category", tag)
#             end
            xml_builder.tag!("dc:subject") do
              xml_builder.tag!("rdf:Bag") do
                for tag in tags
                  xml_builder.tag!("rdf:li", tag)
                end
              end
            end
            if self.feed.podcast?
              xml_builder.tag!("itunes:keywords", tags.join(", "))
            end
          end
          unless self.enclosures.blank? || self.enclosures.size == 0
            for enclosure in self.enclosures
              attribute_hash = {}
              next if enclosure.url.blank?
              begin
                if enclosure.file_size.blank? || enclosure.file_size.to_i == 0
                  # We can't use this enclosure because it's missing the
                  # required file size.  Check alternate versions for
                  # file_size.
                  if !enclosure.versions.blank? && enclosure.versions.size > 0
                    for alternate in enclosure.versions
                      if alternate.file_size != nil &&
                          alternate.file_size.to_i > 0
                        enclosure = alternate
                        break
                      end
                    end
                  end
                end
              rescue
              end
              attribute_hash["url"] = FeedTools.normalize_url(enclosure.url)
              if enclosure.type != nil
                attribute_hash["type"] = enclosure.type
              end
              if enclosure.file_size != nil && enclosure.file_size.to_i > 0
                attribute_hash["length"] = enclosure.file_size.to_s
              else
                # We couldn't find an alternate and the problem is still
                # there.  Give up and go on.
                xml_builder.comment!(
                  "*** Enclosure failed to include file size. Ignoring. ***")
                next
              end
              xml_builder.enclosure(attribute_hash)
            end
          end
          build_xml_hook(feed_type, version, xml_builder)
        end
      elsif feed_type == "atom" && version == 0.3
        raise "Atom 0.3 is obsolete."
      elsif feed_type == "atom" && version == 1.0
        # normal atom format
        return xml_builder.entry("xmlns" =>
            FEED_TOOLS_NAMESPACES['atom10']) do
          unless title.nil? || title == ""
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
          unless link.nil? || link == ""
            xml_builder.link("href" => FeedTools.escape_entities(self.link),
                "rel" => "alternate",
                "title" => FeedTools.escape_entities(title))
          end
          if !self.content.blank?
            xml_builder.content(self.content,
                "type" => "html")
          end
          if !self.summary.blank?
            xml_builder.summary(self.summary,
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
          unless self.published.nil?
            xml_builder.published(self.published.iso8601)            
          end
          if self.id != nil
            unless FeedTools.is_uri? self.id
              if self.time != nil && self.link != nil
                xml_builder.id(FeedTools.build_tag_uri(self.link, self.time))
              elsif self.link != nil
                xml_builder.id(FeedTools.build_urn_uuid_uri(self.link))
              else
                raise "The unique id must be a URI. " +
                  "(Attempted to generate id, but failed.)"
              end
            else
              xml_builder.id(self.id)
            end
          elsif self.time != nil && self.link != nil
            xml_builder.id(FeedTools.build_tag_uri(self.link, self.time))
          else
            raise "Cannot build feed, missing feed unique id."
          end
          unless self.tags.nil? || self.tags.size == 0
            for tag in self.tags
              xml_builder.category("term" => tag)
            end
          end
          unless self.enclosures.blank? || self.enclosures.size == 0
            for enclosure in self.enclosures
              attribute_hash = {}
              next if enclosure.url.blank?
              attribute_hash["rel"] = "enclosure"
              attribute_hash["href"] = FeedTools.normalize_url(enclosure.url)
              if enclosure.type != nil
                attribute_hash["type"] = enclosure.type
              end
              if enclosure.file_size != nil && enclosure.file_size.to_i > 0
                attribute_hash["length"] = enclosure.file_size.to_s
              end
              xml_builder.link(attribute_hash)
            end
          end
          build_xml_hook(feed_type, version, xml_builder)
        end
      else
        raise "Unsupported feed format/version."
      end
    end
    
    alias_method :abstract, :summary
    alias_method :abstract=, :summary=
    alias_method :description, :summary
    alias_method :description=, :summary=
    alias_method :guid, :id
    alias_method :guid=, :id=
    
    # Returns a simple representation of the feed item object's state.
    def inspect
      return "#<FeedTools::FeedItem:0x#{self.object_id.to_s(16)} " +
        "LINK:#{self.link}>"
    end
  end
end
