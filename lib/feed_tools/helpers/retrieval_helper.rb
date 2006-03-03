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
require 'net/http'

# TODO: Not used yet, don't load since it'll only be a performance hit
#  require 'net/https'
#  require 'net/ftp'

# Stolen from the Universal Feed Parser
FEED_TOOLS_ACCEPT_HEADER = "application/atom+xml,application/rdf+xml," +
  "application/rss+xml,application/x-netcdf,application/xml;" +
  "q=0.9,text/xml;q=0.2,*/*;q=0.1"

# TODO: Refactor http_fetch and other methods.
module FeedTools
  # Methods for pulling remote data
  module RetrievalHelper
  end
end