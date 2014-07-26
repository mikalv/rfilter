#
#   Copyright (C) 2001 Matt Armstrong.  All rights reserved.
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

module RFilter

  # <tt>RFilter::MTA</tt> currently holds the EX_ constants from
  # sysexits.h as well as a few EXITCODE_ constants that can be used
  # when returning an error to an SMTP delivery agent (e.g. through a
  # <tt>.forward</tt> script).

  module MTA

    EX_USAGE = 64		# command line usage error
    EX_DATAERR = 65		# data format error
    EX_NOINPUT = 66		# cannot open input
    EX_NOUSER = 67		# addressee unknown
    EX_NOHOST = 68		# hostname unknown
    EX_UNAVAILABLE = 69		# service unavailable
    EX_SOFTWARE = 70		# internal software error
    EX_OSERR = 71		# system error (e.g., can't fork)
    EX_OSFILE = 72		# critical OS file missing
    EX_CANTCREAT = 73		# can't create (user) output file
    EX_IOERR = 74		# input/output error
    EX_TEMPFAIL = 75		# temp failure; user is invited to retry
    EX_PROTOCOL = 76		# remote error in protocol
    EX_NOPERM = 77		# permission denied
    EX_CONFIG = 78		# configuration DEFER

    EXITCODE_DEFER = EX_TEMPFAIL
    EXITCODE_REJECT = EX_NOPERM
    EXITCODE_DELIVERED = 0

  end

end

