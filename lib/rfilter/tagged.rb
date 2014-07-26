#
#   Copyright (C) 2002 Matt Armstrong.  All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. The name of the author may not be used to endorse or promote
#    products derived from this software without specific prior
#    written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
# GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
# IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
# IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

require 'mail/address'
require 'hmac-sha1'

module RFilter
  class AddressTagger

    attr :key, true
    attr :delimiter, true
    attr :strength, true

    def initialize(key, delimiter, strength)
      @key = key
      @delimiter = delimiter
      @strength = strength
    end

    # expires is the absolute time this dated address will expire.
    # E.g. Time.now + (60 * 60 * 24 * age)
    def dated(address, expires)
      tag_address(address, expires.strftime("%Y%m%d%H%S"), 'd')
    end

    def keyword(address, keyword)
      tag_address(address, keyword.downcase.gsub(/[^\w\d]/, '_'), 'k')
    end

    # Returns true if an address verifies.  I.e. that the text portion
    # of the tag matches its HMAC.  Throws an ArgumentError if the
    # address isn't tagged at all.
    def verify(address)
      text, type, hmac = tag_parts(address)
      raise ArgumentError, "address not tagged" unless hmac
      hmac_digest(text, hmac.length / 2) == hmac
    end

    private

    def tag_address(address, text, type)
      address = address.dup
      cookie = hmac_digest(text, @strength)
      address.local = format("%s%s%s.%s.%s", address.local,
                             delimiter, text, type, cookie)
      address
    end

    def hmac_digest(text, strength)
      HMAC::SHA1.digest(@key, text)[0...strength].unpack("H*")[0]
    end

    def tag_parts(address)
      d = Regexp.quote(@delimiter)
      if address.local =~ /#{d}([\w\d]+)\.([\w]+)\.([0-9a-h]+)$/i
            [$1, $2, $3]
          end
      end
    end
end
