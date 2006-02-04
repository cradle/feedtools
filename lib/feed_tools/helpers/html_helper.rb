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
  # Methods for pulling remote data
  module HtmlHelper
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
          type == "application/xhtml+xml" ||
          content_node.namespace == FEED_TOOLS_NAMESPACES['xhtml']
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
      if FeedTools.configurations[:tab_spaces] != nil
        spaces = FeedTools.configurations[:tab_spaces].to_i
        content.gsub!("\t", " " * spaces) unless content.blank?
      end
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
    
    # Given a block of html, locates feed links with a given mime type.
    def extract_autodiscovery_href(html, mime_type)
    end
  end
end