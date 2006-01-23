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
      assert_equal("Example <b>Atom</b>", feed.title)
    }
    with_feed(:from_file =>
        'wellformed/atom/feed_title_base64_2.xml') { |feed|
      assert_equal("<p>History of the &lt;blink&gt; tag</p>", feed.title)
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
  end

  def test_feed_copyright
    with_feed(:from_file =>
        'wellformed/atom/feed_copyright_base64.xml') { |feed|
      assert_equal("Example <b>Atom</b>", feed.copyright)
    }
    with_feed(:from_file =>
        'wellformed/atom/feed_copyright_base64_2.xml') { |feed|
      assert_equal("<p>History of the &lt;blink&gt; tag</p>", feed.copyright)
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
end

