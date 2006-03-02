require 'test/unit'
require 'feed_tools'
require 'feed_tools/helpers/feed_tools_helper'

class AtomTest < Test::Unit::TestCase
  include FeedTools::FeedToolsHelper
  
  def setup
    FeedTools.reset_configurations
    FeedTools.configurations[:tidy_enabled] = false
    FeedTools.configurations[:feed_cache] = "FeedTools::DatabaseFeedCache"
    FeedTools::FeedToolsHelper.default_local_path = 
      File.expand_path(
        File.expand_path(File.dirname(__FILE__)) + '/../feeds')
  end

  def test_iri_feed
    if FeedTools::UriHelper.idn_enabled?
      with_feed(:from_url =>
          'http://www.詹姆斯.com/atomtests/iri/everything.atom') { |feed|
        assert_equal(
          "http://www.xn--8ws00zhy3a.com/atomtests/iri/everything.atom",
          feed.url)
      }
    end
  end
  
  def test_feed_title
    with_feed(:from_file => 'wellformed/atom/atom_namespace_1.xml') { |feed|
      assert_equal("Example Atom", feed.title)
    }
    with_feed(:from_file => 'wellformed/atom/atom_namespace_2.xml') { |feed|
      assert_equal("Example Atom", feed.title)
    }
    with_feed(:from_file => 'wellformed/atom/atom_namespace_3.xml') { |feed|
      assert_equal("Example Atom", feed.title)
    }
    with_feed(:from_file => 'wellformed/atom/atom_namespace_4.xml') { |feed|
      assert_equal("Example Atom", feed.title)
    }
    with_feed(:from_file => 'wellformed/atom/atom_namespace_5.xml') { |feed|
      assert_equal("Example Atom", feed.title)
    }
    with_feed(:from_file => 'wellformed/atom/feed_title_base64.xml') { |feed|
      assert_equal("Example &lt;b&gt;Atom&lt;/b&gt;", feed.title)
    }
    with_feed(:from_file =>
        'wellformed/atom/feed_title_base64_2.xml') { |feed|
      assert_equal(
        "&lt;p&gt;History of the &amp;lt;blink&amp;gt; tag&lt;/p&gt;",
        feed.title)
    }
  end
  
  def test_feed_link
    with_feed(:from_data => <<-FEED
      <feed version="0.3" xmlns="http://purl.org/atom/ns#">
        <link rel="alternate" href="http://www.example.com/" />
        <link rel="alternate" href="http://www.example.com/somewhere/" />
      </feed>
    FEED
    ) { |feed|
      assert_equal("http://www.example.com/", feed.link)
      assert_equal(0, feed.images.size)
    }
    with_feed(:from_data => <<-FEED
      <feed version="0.3" xmlns="http://purl.org/atom/ns#">
        <link type="text/html" href="http://www.example.com/" />
      </feed>
    FEED
    ) { |feed|
      assert_equal("http://www.example.com/", feed.link)
      assert_equal(0, feed.images.size)
    }
    with_feed(:from_data => <<-FEED
      <feed version="0.3" xmlns="http://purl.org/atom/ns#">
        <link type="application/xhtml+xml" href="http://www.example.com/" />
      </feed>
    FEED
    ) { |feed|
      assert_equal("http://www.example.com/", feed.link)
      assert_equal(0, feed.images.size)
    }
    with_feed(:from_data => <<-FEED
      <feed version="0.3" xmlns="http://purl.org/atom/ns#">
        <link href="http://www.example.com/" />
      </feed>
    FEED
    ) { |feed|
      assert_equal("http://www.example.com/", feed.link)
      assert_equal(0, feed.images.size)
    }
    with_feed(:from_data => <<-FEED
      <feed version="0.3" xmlns="http://purl.org/atom/ns#">
        <link rel="alternate" type="image/jpeg"
              href="http://www.example.com/something.jpeg" />
        <link rel="alternate" href="http://www.example.com/" />
        <link rel="alternate" type="text/html"
              href="http://www.example.com/somewhere/" />
        <link rel="alternate" type="application/xhtml+xml"
              href="http://www.example.com/xhtml/somewhere/" />
      </feed>
    FEED
    ) { |feed|
      assert_equal("http://www.example.com/xhtml/somewhere/", feed.link)
      assert_equal(1, feed.images.size)
      assert_equal("http://www.example.com/something.jpeg",
        feed.images[0].url)
    }
    with_feed(:from_data => <<-FEED
      <feed>
        <entry xml:base="http://example.com/articles/">
          <title>Pain And Suffering</title>
          <link href="1.html" type="text/plain" />
          <link href="./2.html" type="application/xml" rel="alternate" />
          <link href="../3.html" type="text/html" rel="alternate" />
          <link href="../4.html" />
          <link href="./5.html" type="application/xhtml+xml" />
          <link href="6.css" type="text/css" rel="stylesheet" />
          <content type="text">
            What does your parser come up with for the main link?
            What's the right value?
          </content>
        </entry>
      </feed>
    FEED
    ) { |feed|
      assert_equal("http://example.com/3.html", feed.entries[0].link)
    }    
  end

  def test_feed_copyright
    with_feed(:from_file =>
        'wellformed/atom/feed_copyright_base64.xml') { |feed|
      assert_equal("Example &lt;b&gt;Atom&lt;/b&gt;", feed.copyright)
    }
    with_feed(:from_file =>
        'wellformed/atom/feed_copyright_base64_2.xml') { |feed|
      assert_equal(
        "&lt;p&gt;History of the &amp;lt;blink&amp;gt; tag&lt;/p&gt;",
        feed.copyright)
    }
  end
  
  def test_feed_item_author
    with_feed(:from_data => <<-FEED
      <?xml version="1.0" encoding="iso-8859-1"?>
      <feed version="0.3" xmlns="http://purl.org/atom/ns#" xml:lang="en">
        <entry>
          <author>
            <name>Cooper Baker</name>    
          </author>
        </entry>
      </feed>
    FEED
    ) { |feed|
      assert_equal(1, feed.entries.size)
      assert_equal("Cooper Baker", feed.entries[0].author.name)
    }
  end
  
  def test_feed_images
    with_feed(:from_data => <<-FEED
      <feed version="0.3" xmlns="http://purl.org/atom/ns#">
        <link type="image/jpeg" href="http://www.example.com/image.jpeg" />
      </feed>
    FEED
    ) { |feed|
      assert_equal(1, feed.images.size)
      assert_equal("http://www.example.com/image.jpeg", feed.images[0].url)
      assert_equal(nil, feed.link)
    }
  end
  
  def test_feed_item_summary_plus_content
    with_feed(:from_data => <<-FEED
      <?xml version="1.0" encoding="iso-8859-1"?>
      <prefix:feed version="1.0" xmlns:prefix="http://www.w3.org/2005/Atom">
        <prefix:entry>
          <prefix:summary>Excerpt</prefix:summary>
          <prefix:content>Full Content</prefix:content>
        </prefix:entry>
      </prefix:feed>
    FEED
    ) { |feed|
      assert_equal(1, feed.items.size)
      assert_equal("Excerpt", feed.items[0].summary)
      assert_equal("Full Content", feed.items[0].content)
    }
  end
  
  # Make sure it knows a title from a hole in the ground
  def test_all_feed_titles
    with_feed(:from_data => <<-FEED
      <?xml version="1.0" encoding="iso-8859-1"?>
      <feed version="1.0" xmlns="http://www.w3.org/2005/Atom">
        <title><![CDATA[&lt;title>]]></title>
        <entry>
          <title><![CDATA[&lt;title>]]></title>
        </entry>
      </feed>
    FEED
    ) { |feed|
      assert_equal("&amp;lt;title&gt;",
        feed.title, "Text CDATA failed")
      assert_equal(1, feed.items.size)
      assert_equal("&amp;lt;title&gt;",
        feed.items[0].title, "Text CDATA failed")
    }
    with_feed(:from_data => <<-FEED
      <?xml version="1.0" encoding="iso-8859-1"?>
      <feed version="1.0" xmlns="http://www.w3.org/2005/Atom">
        <title type="html"><![CDATA[&lt;title>]]></title>
        <entry>
          <title type="html"><![CDATA[&lt;title>]]></title>
        </entry>
      </feed>
    FEED
    ) { |feed|
      assert_equal("&lt;title&gt;",
        feed.title, "HTML CDATA failed")
      assert_equal(1, feed.items.size)
      assert_equal("&lt;title&gt;",
        feed.items[0].title, "HTML CDATA failed")
    }
    with_feed(:from_data => <<-FEED
      <?xml version="1.0" encoding="iso-8859-1"?>
      <feed version="1.0" xmlns="http://www.w3.org/2005/Atom">
        <title type="html">&amp;lt;title></title>
        <entry>
          <title type="html">&amp;lt;title></title>
        </entry>
      </feed>
    FEED
    ) { |feed|
      assert_equal("&lt;title>",
        feed.title, "HTML entity failed")
      assert_equal(1, feed.items.size)
      assert_equal("&lt;title>",
        feed.items[0].title, "HTML entity failed")
    }
    with_feed(:from_data => <<-FEED
      <?xml version="1.0" encoding="iso-8859-1"?>
      <feed version="1.0" xmlns="http://www.w3.org/2005/Atom">
        <title type="html">&#38;lt;title></title>
        <entry>
          <title type="html">&#38;lt;title></title>
        </entry>
      </feed>
    FEED
    ) { |feed|
      assert_equal("&lt;title>",
        feed.title, "HTML NCR failed")
      assert_equal(1, feed.items.size)
      assert_equal("&lt;title>",
        feed.items[0].title, "HTML NCR failed")
    }
    with_feed(:from_data => <<-FEED
      <?xml version="1.0" encoding="iso-8859-1"?>
      <feed version="1.0" xmlns="http://www.w3.org/2005/Atom">
        <title type="text"><![CDATA[<title>]]></title>
        <entry>
          <title type="text"><![CDATA[<title>]]></title>
        </entry>
      </feed>
    FEED
    ) { |feed|
      assert_equal("&lt;title&gt;",
        feed.title, "Text CDATA failed")
      assert_equal(1, feed.items.size)
      assert_equal("&lt;title&gt;",
        feed.items[0].title, "Text CDATA failed")
    }
    with_feed(:from_data => <<-FEED
      <?xml version="1.0" encoding="iso-8859-1"?>
      <feed version="1.0" xmlns="http://www.w3.org/2005/Atom">
        <title type="text">&lt;title></title>
        <entry>
          <title type="text">&lt;title></title>
        </entry>
      </feed>
    FEED
    ) { |feed|
      assert_equal("&lt;title&gt;",
        feed.title, "Text entity failed")
      assert_equal(1, feed.items.size)
      assert_equal("&lt;title&gt;",
        feed.items[0].title, "Text entity failed")
    }
    with_feed(:from_data => <<-FEED
      <?xml version="1.0" encoding="iso-8859-1"?>
      <feed version="1.0" xmlns="http://www.w3.org/2005/Atom">
        <title type="text">&#60;title></title>
        <entry>
          <title type="text">&#60;title></title>
        </entry>
      </feed>
    FEED
    ) { |feed|
      assert_equal("&lt;title&gt;",
        feed.title, "Text NCR failed")
      assert_equal(1, feed.items.size)
      assert_equal("&lt;title&gt;",
        feed.items[0].title, "Text NCR failed")
    }
    with_feed(:from_data => <<-FEED
      <?xml version="1.0" encoding="iso-8859-1"?>
      <feed version="1.0" xmlns="http://www.w3.org/2005/Atom">
        <title type="xhtml">
          <div xmlns="http://www.w3.org/1999/xhtml">&lt;title></div>
        </title>
        <entry>
          <title type="xhtml">
            <div xmlns="http://www.w3.org/1999/xhtml">&lt;title></div>
          </title>
        </entry>
      </feed>
    FEED
    ) { |feed|
      assert_equal(
        '&lt;title&gt;',
        feed.title, "XHTML entity failed")
      assert_equal(1, feed.items.size)
      assert_equal(
        '&lt;title&gt;',
        feed.items[0].title, "XHTML entity failed")
    }
    with_feed(:from_data => <<-FEED
      <?xml version="1.0" encoding="iso-8859-1"?>
      <feed version="1.0" xmlns="http://www.w3.org/2005/Atom">
        <title type="xhtml">
          <div xmlns="http://www.w3.org/1999/xhtml">&#60;title></div>
        </title>
        <entry>
          <title type="xhtml">
            <div xmlns="http://www.w3.org/1999/xhtml">&#60;title></div>
          </title>
        </entry>
      </feed>
    FEED
    ) { |feed|
      assert_equal(
        '&#60;title&gt;',
        feed.title, "XHTML NCR failed")
      assert_equal(1, feed.items.size)
      assert_equal(
        '&#60;title&gt;',
        feed.items[0].title, "XHTML NCR failed")
    }
    with_feed(:from_data => <<-FEED
      <?xml version="1.0" encoding="iso-8859-1"?>
      <feed version="1.0" xmlns="http://www.w3.org/2005/Atom">
        <title type="xhtml" xmlns:xhtml="http://www.w3.org/1999/xhtml">
          <xhtml:div>&lt;title></xhtml:div>
        </title>
        <entry>
          <title type="xhtml" xmlns:xhtml="http://www.w3.org/1999/xhtml">
            <xhtml:div>&lt;title></xhtml:div>
          </title>
        </entry>
      </feed>
    FEED
    ) { |feed|
      assert_equal(
        '&lt;title&gt;',
        feed.title, "XHTML NCR failed")
      assert_equal(1, feed.items.size)
      assert_equal(
        '&lt;title&gt;',
        feed.items[0].title, "XHTML NCR failed")
    }
  end
end