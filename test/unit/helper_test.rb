require 'test/unit'
require 'feed_tools'
require 'feed_tools/helpers/feed_tools_helper'

class HelperTest < Test::Unit::TestCase
  include FeedTools::FeedToolsHelper
  include FeedTools::GenericHelper

  def setup
    FeedTools.reset_configurations
    FeedTools.configurations[:tidy_enabled] = false
    FeedTools.configurations[:feed_cache] = "FeedTools::DatabaseFeedCache"
    FeedTools::FeedToolsHelper.default_local_path = 
      File.expand_path(
        File.expand_path(File.dirname(__FILE__)) + '/../feeds')
  end

  def test_xpath_case_insensitivity
    FEED_TOOLS_NAMESPACES["testnamespace"] = "http://example.com/ns/"
    
    xml = <<-XML
      <RoOt>
        <ChIlD>Test String #1</ChIlD>
      </RoOt>
    XML
    xml_doc = REXML::Document.new(xml)
    test_string = try_xpaths(xml_doc, [
      "ROOT/child/text()"
    ], :select_result_value => true)
    assert_equal("Test String #1", test_string)

    xml = <<-XML
      <root xmlns:TESTnAmEsPace="http://example.com/ns/">
        <TESTnAmEsPace:ChIlD>Test String #2</TESTnAmEsPace:ChIlD>
      </root>
    XML
    xml_doc = REXML::Document.new(xml)
    test_string = try_xpaths(xml_doc, [
      "ROOT/testnamespace:child/text()"
    ], :select_result_value => true)
    assert_equal("Test String #2", test_string)

    xml = <<-XML
      <RoOt>
        <ChIlD AttRib="Test String #3" />
      </RoOt>
    XML
    xml_doc = REXML::Document.new(xml)
    test_string = try_xpaths(xml_doc, [
      "ROOT/child/@ATTRIB"
    ], :select_result_value => true)
    assert_equal("Test String #3", test_string)

    xml = <<-XML
      <RoOt xmlns:TESTnAmEsPace="http://example.com/ns/">
        <ChIlD TESTnAmEsPace:AttRib="Test String #4" />
      </RoOt>
    XML
    xml_doc = REXML::Document.new(xml)
    test_string = try_xpaths(xml_doc, [
      "ROOT/child/@testnamespace:ATTRIB"
    ], :select_result_value => true)
    assert_equal("Test String #4", test_string)
  end

  def test_escape_entities
  end

  def test_unescape_entities
  end
  
  def test_normalize_url
    assert_equal("http://slashdot.org/",
      FeedTools.normalize_url("slashdot.org"))
    assert_equal("http://example.com/index.php",
      FeedTools.normalize_url("example.com/index.php"))

    # Test windows-style file: protocol normalization
    assert_equal("file:///c:/windows/My%20Documents%20100%20/foo.txt",
      FeedTools.normalize_url("c:\\windows\\My Documents 100%20\\foo.txt"))
    assert_equal("file:///c:/windows/My%20Documents%20100%20/foo.txt",
      FeedTools.normalize_url(
        "file://c:\\windows\\My Documents 100%20\\foo.txt"))
    assert_equal("file:///c:/windows/My%20Documents%20100%20/foo.txt",
      FeedTools.normalize_url(
        "file:///c|/windows/My%20Documents%20100%20/foo.txt"))
    assert_equal("file:///c:/windows/My%20Documents%20100%20/foo.txt",
      FeedTools.normalize_url(
        "file:///c:/windows/My%20Documents%20100%20/foo.txt"))
  end
  
  def test_sanitize_html
    assert_equal("<!--foo-->", FeedTools.sanitize_html("<!--foo-->"))
    assert_equal("<P>Upper-case tags</P>",
      FeedTools.sanitize_html("<P>Upper-case tags</P>"))
    assert_equal("<A HREF='/dev/null'>Upper-case attributes</A>",
      FeedTools.sanitize_html(
        "<A HREF='/dev/null'>Upper-case attributes</A>"))
  end
  
  def test_tidy_html
    FeedTools.configurations[:tidy_enabled] = true
    unless FeedTools.tidy_enabled?
      puts "\nCould not test tidy support.  Libtidy couldn't be found."
    else
      illegal_pre = <<-EOF
        <pre>
         require 'net/http'
         module Net
         class HTTPIO < HTTP
           def request(req, body = nil, &#38;block)
             begin_transport req
             req.exec @socket, @curr_http_version, edit_path(req.path), body
             begin
               res = HTTPResponse.read_new(@socket)
             end while HTTPContinue === res

             res.instance_eval do
               def read len = nil; ... end
               def body; true end
               def close
                 req, res = @req, self
                 @http.instance_eval do
                    end_transport req, res
                    finish
                 end
               end
               def size; 0 end
               def is_a? klass; klass == IO ? true : super(klass); end
             end

             res
           end
         end
        </pre>
      EOF
      illegal_pre_after_tidy = FeedTools.tidy_html(illegal_pre)
      assert_not_equal(nil, illegal_pre_after_tidy =~ /class HTTPIO &lt; HTTP/,
        "Tidy failed to clean up illegal chars in <pre> block.")
    end
    FeedTools.configurations[:tidy_enabled] = false
  end
  
  def test_build_urn_uri
    assert_equal("urn:uuid:fa6d0b87-3f36-517d-b9b7-1349f8c3fc6b",
      FeedTools.build_urn_uri('http://sporkmonger.com/'))
  end
end