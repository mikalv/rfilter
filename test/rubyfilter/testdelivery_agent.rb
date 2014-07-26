#
#   Copyright (C) 2001, 2002, 2003 Matt Armstrong.  All rights reserved.
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

require 'test/rubyfilter/testbase'
require 'rfilter/delivery_agent'

module RFilter
  module Test
    class TestRFilterDeliveryAgent < TestBase

      @@count = 0
      FROM_RE = /^From .*?@.*?  (Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [ \d]\d \d{2}:\d{2}:\d{2} \d{4}/

      def setup
        super

        @message_string = <<-EOF
        From: test-from@example.com
        To: test-to@example.com
        Subject: this is a test message

        From test
        EOF
        @message_string.freeze

      end

      # Make sure the maildir file holds the same message as
      # @message_string
      def validate_maildir_message(delivered_to)
        lines = IO.readlines(delivered_to)
        assert_equal("From: test-from@example.com\n", lines[0])
        assert_equal("To: test-to@example.com\n", lines[1])
        assert_equal("Subject: this is a test message\n", lines[2])
        assert_equal("\n", lines[3])
        assert_equal("From test\n", lines[4])
        assert_equal(nil, lines[5])
      end

      # Make sure the unix mbox file holds the same message as
      # @message_string
      def validate_mbox(mailbox)
        lines = IO.readlines(mailbox)
        assert_match(FROM_RE, lines[0])
        lines.shift
        assert_equal("From: test-from@example.com\n", lines[0])
        assert_equal("To: test-to@example.com\n", lines[1])
        assert_equal("Subject: this is a test message\n", lines[2])
        assert_equal("\n", lines[3])
        assert_equal(">From test\n", lines[4])
        assert_equal("\n", lines[5])
        assert_equal(nil, lines[6])
      end

      def new_lda()
        log = scratch_filename("lda-log")
        lda = string_as_file(@message_string) { |file|
          RFilter::DeliveryAgent.new(file, log)
        }
        assert_not_nil(lda)
        assert(test(?e, log))
        [lda, log]
      end

      def errors_in_logfile(logfile)
        file_contains(logfile, /exception|backtrace|error/i)
      end

      def test_defer()
        begin
          defer_reason = "I might not like you any more"
          lda, log = new_lda
          e = assert_exception(RFilter::DeliveryAgent::DeliveryDefer) {
            lda.defer(defer_reason)
          }
          assert_equal(e.message, defer_reason)
          assert(file_contains(log, Regexp.new(Regexp.escape(defer_reason))))
          assert(!errors_in_logfile(log))
        end
        begin
          lda, log = new_lda
          e = assert_exception(RFilter::DeliveryAgent::DeliveryDefer) {
            lda.defer
          }
          assert_equal(e.message, "")
          assert(file_contains(log, "Action: defer:"))
          assert(!errors_in_logfile(log))
        end
      end

      def test_reject()
        begin
          reject_reason = "I don't like you any more"
          lda, log = new_lda
          e = assert_exception(RFilter::DeliveryAgent::DeliveryReject) {
            lda.reject(reject_reason)
          }
          assert_equal(e.message, reject_reason)
          assert(file_contains(log, Regexp.new(Regexp.escape(reject_reason))))
          assert(!errors_in_logfile(log))
        end

        begin
          lda, log = new_lda
          e = assert_exception(RFilter::DeliveryAgent::DeliveryReject) {
            lda.reject
          }
          assert_equal(e.message, "")
          assert(file_contains(log, Regexp.new(Regexp.escape("Action: reject:"))))
          assert(!errors_in_logfile(log))
        end
      end

      def test_message=()
        m = RMail::Message.new
        lda, log = new_lda
        assert_same(m, lda.message = m)
        assert_same(m, lda.message)
      end

      def process_boilerplate(nolog = false)
        log = scratch_filename("process-log") unless nolog
        log ||= nil
        string_as_file(@message_string) {|file|
          RFilter::DeliveryAgent.process(file, log) { |lda|
            yield(lda, log)
          }
        }
      end

      def test_process()
        log = nil

        # Test what happens when the lda script does nothing
        e = assert_exception(RFilter::DeliveryAgent::DeliveryDefer) {
          process_boilerplate { |lda, log|
            assert_not_nil(lda)
            assert_not_nil(log)
            # do nothing
          }
        }
        assert_equal("finished without a final delivery", e.message)
        assert(file_contains(log,
                             /Action: defer: finished without a final delivery/))

        # Test what happens when the lda script raises a random exception
        e = assert_exception(RFilter::DeliveryAgent::DeliveryDefer) {
          process_boilerplate { |lda, log|
            assert_not_nil(lda)
            assert_not_nil(log)
            lda.log(1, "about to raise an exception")
            raise "URP!"
          }
        }
        assert_equal("uncaught exception", e.message)
        assert(file_contains(log, /uncaught exception: .*RuntimeError.* URP!/))
        assert(file_contains(log, /uncaught exception backtrace:/))

        # Test what happens when the lda script raises a random exception
        # when there is no log
        e = assert_exception(RuntimeError) {
          process_boilerplate(true) { |lda, log|
            assert_not_nil(lda)
            assert_nil(log)
            lda.log(1, "about to raise an exception")
            raise "raised within the lda.process block"
          }
        }
        assert_equal("raised within the lda.process block", e.message)

        # Test what happens when the lda script actually delivers
        mailbox = scratch_filename("mailbox")
        e = assert_exception(RFilter::DeliveryAgent::DeliverySuccess) {
          process_boilerplate { |lda, log|
            assert_not_nil(lda)
            assert_not_nil(log)
            lda.save(mailbox)
          }
        }
        mailbox_re = Regexp::escape(mailbox.inspect)
        assert_match(/^saved to mbox #{mailbox_re}$/, e.message)
        assert(file_contains(log, /\bAction: save to #{mailbox_re}$/))
        validate_mbox(mailbox)
      end

      def test_exitcode()
        e = assert_exception(ArgumentError) {
          RFilter::DeliveryAgent.exitcode(5)
        }
        assert_equal("argument is not a DeliveryComplete exception: 5 (Fixnum)",
                     e.message)

        e = assert_exception(ArgumentError) {
          RFilter::DeliveryAgent.exitcode(RuntimeError.new("hi mom!"))
        }
        assert_match(/argument is not a DeliveryComplete exception: .*RuntimeError/,
                     e.message)

        assert_equal(RFilter::MTA::EXITCODE_DELIVERED,
                     RFilter::DeliveryAgent.exitcode(RFilter::DeliveryAgent::DeliverySuccess.new("")))
        assert_equal(RFilter::MTA::EXITCODE_REJECT,
                     RFilter::DeliveryAgent.exitcode(RFilter::DeliveryAgent::DeliveryReject.new("")))
        assert_equal(RFilter::MTA::EXITCODE_DEFER,
                     RFilter::DeliveryAgent.exitcode(RFilter::DeliveryAgent::DeliveryDefer.new("")))
        assert_exception(ArgumentError) {
          RFilter::DeliveryAgent.exitcode(RFilter::DeliveryAgent::LoggingError.new(""))
        }
        assert_equal(RFilter::MTA::EXITCODE_DEFER,
                     RFilter::DeliveryAgent.exitcode(RFilter::DeliveryAgent::DeliveryCommandFailure.new("", 1)))
        assert_equal(RFilter::MTA::EXITCODE_DEFER,
                     RFilter::DeliveryAgent.exitcode(RFilter::DeliveryAgent::DeliveryComplete.new("")))
      end

      def test_save()
        # Test successful delivery with a real message with no mbox_from
        mailbox = scratch_filename("mailbox")
        lda, log = new_lda
        lda.header.mbox_from = nil
        lda.save(mailbox, true)
        assert_equal(true, test(?e, mailbox))
        assert_equal(true, test(?e, log))
        assert(!errors_in_logfile(log))
        validate_mbox(mailbox)

        # Test successful delivery with a real message that has a
        # mbox_from
        mailbox = scratch_filename("mailbox")
        lda, log = new_lda
        lda.header.mbox_from = "From matt@example.com  Mon Dec 24 00:00:06 2001"
        lda.save(mailbox, true)
        assert_equal(true, test(?e, mailbox))
        assert_equal(true, test(?e, log))
        assert(!errors_in_logfile(log))
        validate_mbox(mailbox)

        # Test successful delivery to a Maildir with a real message that
        # has a mbox_from
        mailbox = scratch_filename("maildir") + '/'
        lda, log = new_lda
        lda.header.mbox_from = "From matt@example.com  Mon Dec 24 00:00:06 2001"
        delivered_to = lda.save(mailbox, true)
        assert(!errors_in_logfile(log))
        validate_maildir_message(delivered_to)

        # Test successful delivery with a real message to an mbox,
        # continue = false
        mailbox = scratch_filename("mailbox")
        assert_equal(false, test(?e, mailbox))
        lda, log = new_lda
        e = assert_exception(RFilter::DeliveryAgent::DeliverySuccess) {
          lda.save(mailbox, false)
        }
        assert_equal("saved to mbox #{mailbox.inspect}", e.message)
        assert_equal(true, test(?e, mailbox))
        assert_equal(true, test(?e, log))
        assert(!errors_in_logfile(log))
        validate_mbox(mailbox)

        # Test successful delivery with a real message to a maildir,
        # continue = false
        mailbox = scratch_filename("maildir") + '/'
        lda, log = new_lda
        e = assert_exception(RFilter::DeliveryAgent::DeliverySuccess) {
          lda.save(mailbox, false)
        }
        assert_equal("saved to mbox #{mailbox.inspect}", e.message)
        assert(!errors_in_logfile(log))
      end

      def test_deliver_pipe
        catfile = scratch_filename("catfile.pipe")
        logfile = scratch_filename("logfile.pipe")
        command = "/bin/cat > #{catfile}"

        lda, log = new_lda
        assert_equal(false, test(?e, catfile))
        assert_equal(true, test(?e, log))

        lda.pipe(command, true)
        assert(test(?e, catfile))
        assert_equal(0, $?, "exit value not propagated")

        command_re = Regexp::escape(command.inspect)
        assert(file_contains(log, /\bAction: pipe to #{command_re}/))
        assert(!errors_in_logfile(log))

        # test that a successful pipe delivery will try to exit
        command = "/bin/cat >> #{catfile}"
        e = assert_exception(RFilter::DeliveryAgent::DeliverySuccess) {
          lda.pipe(command)
        }
        assert_equal("pipe to #{command.inspect}", e.message)

        assert(file_contains(log,
                             /\bAction: pipe to #{Regexp::escape(command.inspect)}/))
        assert(!errors_in_logfile(log))
      end

      def test_deliver_pipe_error
        # test with continue = true
        lda, log = new_lda
        command = "/bin/sh -c \"exit 32\""
        e = assert_exception(RFilter::DeliveryAgent::DeliveryCommandFailure) {
          lda.pipe(command, true)
        }
        assert_equal(32 << 8, e.status)
        assert_equal("pipe failed for command #{command.inspect}", e.message)
        command_re = Regexp::escape(command.inspect)
        assert(file_contains(log, /\bAction: pipe to #{command_re}/))
        assert(errors_in_logfile(log))

        # test with continue = false
        lda, log = new_lda
        command = "/bin/sh -c \"exit 1\""
        e = assert_exception(RFilter::DeliveryAgent::DeliveryCommandFailure) {
          lda.pipe(command, false)
        }
        assert_equal("pipe failed for command #{command.inspect}", e.message)
        assert_equal(1 << 8, e.status)
        command_re = Regexp::escape(command.inspect)
        assert(file_contains(log, /\bAction: pipe to #{command_re}/))
      end

      def test_deliver_filter_simple
        lda, log = new_lda
        command = [ ruby_program, '-pe', ';' ]
        old_message = lda.message
        lda.filter(*command)
        assert(old_message.__id__ != lda.message.__id__)
        assert_equal(old_message, lda.message)
        assert(!errors_in_logfile(log))
      end

      def test_deliver_filter_epipe()
        lda, log = new_lda
        script = <<-EOF
        while line = gets
          # exit early without reading all of the contents
          exit(0) if line =~ /^Subject:/i
          puts line
        end
        EOF
        command = [ ruby_program, '-pe', script ]
        old_message = lda.message
        lda.filter(*command)
        assert(old_message.__id__ != lda.message.__id__)
        assert(old_message != lda.message)
        assert(old_message.header.field?('subject'))
        assert(!lda.message.header.field?('subject'))
        assert(!errors_in_logfile(log))
      end

      def test_deliver_filter_failed()
        lda, log = new_lda
        script = <<-EOF
        while line = gets
          # exit early without reading all of the contents
          exit(60) if line =~ /^Subject:/i
          puts line
        end
        EOF
        command = [ ruby_program, '-pe', script ]
        old_message = lda.message
        e = assert_exception(RFilter::DeliveryAgent::DeliveryCommandFailure) {
          lda.filter(*command)
        }
        assert_match(/failed.*exit\(60\)/, e.message)
        assert_same(old_message, lda.message)
        assert(errors_in_logfile(log))
      end

      def test_deliver_filter_failed2()
        lda, log = new_lda
        command = [ '/this/command/does/not/exist' ]
        old_message = lda.message
        e = assert_exception(RFilter::DeliveryAgent::DeliveryCommandFailure) {
          lda.filter(*command)
        }
        assert_match(/failed for command.*does\/not\/exist/, e.message)
        assert_same(old_message, lda.message)
        assert(errors_in_logfile(log))
      end

      def test_nil_log
        lda = nil
        string_as_file(@message_string) { |f|
          lda = RFilter::DeliveryAgent.new(f, nil)
        }
        lda.logging_level = 10
        lda.log(1, "this is ignored")
        e = assert_exception(RFilter::DeliveryAgent::LoggingError) {
          lda.log(0, "this should raise an exception")
        }
        assert_match(/failed to log high priority message: this should raise an exception/, e.message)
        assert_equal(nil, e.original_exception)
      end

      def test_log
        lda, log = new_lda

        # Default logging level is 2
        assert_equal(2, lda.logging_level)

        # First make sure we get errors when we set log level to
        # something bogus.
        assert_exception(ArgumentError) {
          lda.logging_level = "foo"
        }
        assert_exception(TypeError) {
          lda.logging_level = Object.new
        }
        e = assert_exception(ArgumentError) {
          lda.logging_level = -1
        }
        assert_match(/invalid logging level value -1/, e.message)
        e = assert_exception(ArgumentError) {
          lda.logging_level = 0
        }
        assert_match(/invalid logging level value 0/, e.message)

        1.upto(5) { |logset|
          lda.logging_level = logset
          0.upto(5) { |logat|
            lda.log(logat, "set#{logset} at#{logat}")
          }
        }

        1.upto(5) { |log_level|
          0.upto(5) { |logat|
            re = /: set#{log_level} at#{logat}/
            contains = file_contains(log, re)
            if logat <= log_level
              assert(contains)
            else
              assert(!contains)
            end
          }
        }
      end

      # Test message access functions of RFilter::DeliveryAgent
      def test_message_access
        lda, log = new_lda

        # Test the message method, to get at the message itself
        assert_respond_to(:message, lda)
        assert_not_nil(lda.message)
        assert_respond_to(:body, lda.message)
        assert_respond_to(:header, lda.message)
        assert_kind_of(RMail::Message, lda.message)

        # Test the header method, to get at the message header itself
        assert_respond_to(:header, lda)
        assert_not_nil(lda.header)
        assert_respond_to(:add, lda.header)
        assert_kind_of(RMail::Header, lda.header)
        assert_same(lda.message.header, lda.header)

        # Test the body method, to get at the message body itself
        assert_respond_to(:body, lda)
        assert_not_nil(lda.body)
        assert_respond_to(:each, lda.body)
        assert_respond_to(:grep, lda.body)
        assert_kind_of(String, lda.body)
        assert_same(lda.message.body, lda.body)
      end
    end
  end
end
