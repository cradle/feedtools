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
require 'rexml/document'

module FeedTools
  # Generic methods needed in numerous places throughout FeedTools
  module GenericHelper
    # Raises an exception if an invalid option has been specified to prevent
    # misspellings from slipping through 
    def validate_options(valid_option_keys, supplied_option_keys)
      unknown_option_keys = supplied_option_keys - valid_option_keys
      unless unknown_option_keys.empty?
        raise "Unknown options: #{unknown_option_keys}"
      end
    end
    
    # Selects the first non-blank result.
    def select_not_blank(results, &block)
      for result in results
        blank_result = false
        if !block.nil?
          blank_result = block.call(result)
        else
          blank_result = result.to_s.blank?
        end
        unless result.nil? || blank_result
          return result
        end
      end
      return nil
    end
    
    # Runs through a list of XPath queries on an element or document and
    # returns the first non-blank result.  Subsequent XPath queries will
    # not be evaluated.
    def try_xpaths(element, xpath_list,
        options={}, &block)
      validate_options([ :select_result_value ],
                       options.keys)
      options = { :select_result_value => false }.merge(options)

      result = nil
      if element.nil?
        return nil
      end
      for xpath in xpath_list
        # Namespace aware
        result = REXML::XPath.liberal_first(element, xpath,
          FEED_TOOLS_NAMESPACES)
        if options[:select_result_value] && !result.nil?
          if result.respond_to?(:value)
            result = result.value
          else
            result = result.to_s
          end
        end
        blank_result = false
        if block_given?
          blank_result = yield(result)
        else
          blank_result = result.to_s.blank?
        end
        if !blank_result
          if result.respond_to? :strip
            result.strip!
          end
          return result
        end
        
        # Namespace unaware
        result = REXML::XPath.liberal_first(element, xpath)
        if options[:select_result_value] && !result.nil?
          if result.respond_to?(:value)
            result = result.value
          else
            result = result.to_s
          end
        end
        blank_result = false
        if block_given?
          blank_result = yield(result)
        else
          blank_result = result.to_s.blank?
        end
        if !blank_result
          if result.respond_to? :strip
            result.strip!
          end
          return result
        end
      end
      return nil
    end
    
    # Runs through a list of XPath queries on an element or document and
    # returns the first non-empty result.  Subsequent XPath queries will
    # not be evaluated.
    def try_xpaths_all(element, xpath_list, options={})
      validate_options([ :select_result_value ],
                       options.keys)
      options = { :select_result_value => false }.merge(options)

      results = []
      if element.nil?
        return []
      end
      for xpath in xpath_list
        results = REXML::XPath.liberal_match(element, xpath,
          FEED_TOOLS_NAMESPACES)
        if options[:select_result_value] && !results.nil? && !results.empty?
          results =
            results.map { |x| x.respond_to?(:value) ? x.value : x.to_s }
        end
        if results.blank?
          results = REXML::XPath.liberal_match(element, xpath)
        else
          return results
        end
        if options[:select_result_value] && !results.nil? && !results.empty?
          results =
            results.map { |x| x.respond_to?(:value) ? x.value : x.to_s }
        end
        if !results.blank?
          return results
        end
      end
      for xpath in xpath_list
        if xpath =~ /^\w+$/
          results = []
          for child in element.children
            if child.class == REXML::Element
              if child.name.downcase == xpath.downcase
                results << child
              end
            end
          end
          if options[:select_result_value] && !results.nil? && !results.empty?
            results =
              results.map { |x| x.inner_xml }
          end
          if !results.blank?
            return results
          end
        end
      end
      return []
    end

    # Returns a string containing normalized xhtml from within a REXML node.
    def extract_xhtml(rexml_node)
      rexml_node_dup = rexml_node.deep_clone
      normalize_namespaced_xhtml = lambda do |node, node_dup|
        if node.kind_of? REXML::Element
          node_namespace = node.namespace
          # Massive hack, relies on REXML not changing
          for index in 0...node.attributes.values.size
            attribute = node.attributes.values[index]
            attribute_dup = node_dup.attributes.values[index]
            if attribute.namespace == FEED_TOOLS_NAMESPACES['xhtml']
              attribute_dup.instance_variable_set(
                "@expanded_name", attribute.name)
            end
            if node_namespace == FEED_TOOLS_NAMESPACES['xhtml']
              if attribute.name == 'xmlns'
                node_dup.attributes.delete('xmlns')
              end
            end
          end
          if node_namespace == FEED_TOOLS_NAMESPACES['xhtml']
            node_dup.instance_variable_set("@expanded_name", node.name)
          end
          if !node_namespace.blank? && node.prefix.blank?
            if node.namespace != FEED_TOOLS_NAMESPACES['xhtml']
              node_dup.add_namespace(node_namespace)
            end
          end
        end
        for index in 0...node.children.size
          child = node.children[index]
          child_dup = node_dup.children[index]
          if child.kind_of? REXML::Element
            normalize_namespaced_xhtml.call(child, child_dup)
          end
        end
      end
      normalize_namespaced_xhtml.call(rexml_node, rexml_node_dup)
      buffer = ""
      rexml_node_dup.each_child do |child|
        if child.kind_of? REXML::Comment
          buffer << "<!--" + child.to_s + "-->"
        else
          buffer << child.to_s
        end
      end
      return buffer.strip
    end
    
    # Given a REXML node, returns its content, normalized as HTML.
    def process_text_construct(content_node, feed_type, feed_version)
      if content_node.nil?
        return nil
      end
      
      content = nil
      root_node_name = nil
      type = try_xpaths(content_node, "@type",
        :select_result_value => true)
      mode = try_xpaths(content_node, "@mode",
        :select_result_value => true)
      encoding = try_xpaths(content_node, "@encoding",
        :select_result_value => true)

      if type.nil?
        atom_namespaces = [
          FEED_TOOLS_NAMESPACES['atom10'],
          FEED_TOOLS_NAMESPACES['atom03']
        ]
        if ((atom_namespaces.include?(content_node.namespace) ||
            atom_namespaces.include?(content_node.root.namespace)) ||
            feed_type == "atom")
          type = "text"
        end
      end
        
      # Note that we're checking for misuse of type, mode and encoding here
      if content_node.cdatas.size > 0
        content = content_node.cdatas.first.to_s.strip
      elsif type == "base64" || mode == "base64" ||
          encoding == "base64"
        content = Base64.decode64(content_node.inner_xml.strip)
      elsif type == "xhtml" || mode == "xhtml" ||
          type == "xml" || mode == "xml" ||
          type == "application/xhtml+xml"
        content = extract_xhtml(content_node)
      elsif type == "escaped" || mode == "escaped"
        content = FeedTools.unescape_entities(
          content_node.inner_xml.strip)
      elsif type == "text" || mode == "text" ||
          type == "text/plain" || mode == "text/plain"
        content = FeedTools.unescape_entities(
          content_node.inner_xml.strip)
      else
        content = content_node.inner_xml.strip
        repair_entities = true
      end
      if type == "text" || mode == "text" ||
          type == "text/plain" || mode == "text/plain"
        content = FeedTools.escape_entities(content)
      end        
      unless content.nil?
        if FeedTools.configurations[:sanitization_enabled]
          content = FeedTools.sanitize_html(content, :strip)
        end
        content = FeedTools.unescape_entities(content) if repair_entities
        content = FeedTools.tidy_html(content)
      end
      content.gsub!("\t", "  ") unless content.blank?
      content.strip unless content.blank?
      content = nil if content.blank?
      return content
    end

    # Strips semantically empty div wrapper elements
    def strip_wrapper_element(xhtml)
      return nil if xhtml.nil?
      return xhtml if xhtml.blank?
      begin
        doc = REXML::Document.new(xhtml.to_s.strip)
        if doc.children.size == 1
          child = doc.children[0]
          if child.name.downcase == "div"
            return child.inner_xml.strip
          end
        end
        return xhtml.to_s.strip
      rescue Exception
        return xhtml.to_s.strip
      end
    end
  end
end