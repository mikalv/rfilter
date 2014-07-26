#--
#   Copyright (C) 2002, 2003 Matt Armstrong.  All rights reserved.
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
require 'rfilter/mta'

module RFilter
  module Test
    class TestRDeliver < TestBase

      attr_reader :home

      def command_line_load_path(path)
        format("-I '%s'", path)
      end

      def rubymail_load_path
        extra_load_paths.collect { |path|
          command_line_load_path(path)
        }.join(' ')
      end

      def setup
        super
        @old_home = ENV['HOME']
        @home = File.join(@scratch_dir, 'home')
        Dir.mkdir(@home)
        ENV['HOME'] = @home
      end

      def teardown
        ENV['HOME'] = @old_home
        super
      end

      def script
        File.join(Dir.getwd, 'bin', 'rdeliver.rb')
      end

      def test_rdeliver_syntax
        assert_equal(true, system(ruby_program + ' -c ' + script + ' >/dev/null'))
      end

      def test_rdeliver_home_arg
        home2 = home + '2'
        Dir.mkdir(home2)
        assert_equal(false, system(ruby_program, script, '--home', home2,
                                   '--bogus'))
        assert_equal(75 << 8, $?)
        catastrophic = File.join(home2, 'CATASTROPHIC_DELIVERY_FAILURE')
        assert(test(?e, catastrophic))
        assert(file_contains(catastrophic, /unrecognized option.*--bogus/))
      end

      def test_rdeliver_load_path_arg
        Dir.mkdir(File.join(scratch_dir, 'rfilter'))
        File.open(File.join(scratch_dir, 'rfilter',
                            'delivery_agent.rb'), 'w') {
          |file|
          file.puts 'raise "test succeeded"'
        }
        assert_equal(false, system(ruby_program, script, '--load-path',
                                   scratch_dir))
        assert_equal(75 << 8, $?)
        catastrophic = File.join(home, 'CATASTROPHIC_DELIVERY_FAILURE')
        assert(test(?e, catastrophic))
        assert(file_contains(catastrophic, /test succeeded/))
      end

      def test_rdeliver_bad_arg
        assert_equal(false, system(ruby_program, script, '--bogus'))
        assert_equal(75 << 8, $?)
        catastrophic = File.join(home, 'CATASTROPHIC_DELIVERY_FAILURE')
        assert(test(?e, catastrophic))
        assert(file_contains(catastrophic, /unrecognized option.*--bogus/))
      end

      def test_extra_arguments
        assert_equal(false, system(ruby_program, script, 'first',
                                   'extra1', 'extra2'))
        assert_equal(75 << 8, $?)
        catastrophic = File.join(home, 'CATASTROPHIC_DELIVERY_FAILURE')
        assert(test(?e, catastrophic))
        assert(file_contains(catastrophic, /RuntimeError/))
        assert(file_contains(catastrophic, /extra arguments passed to.*\["extra1", "extra2"\]/))
      end

      def test_homedir_chdir_failure
        Dir.rmdir(home)
        errors = scratch_filename('errors')
        assert_equal(false, system(format("'%s' '%s' --bogus > %s",
                                          ruby_program, script, errors)))
        assert_equal(75 << 8, $?)
        catastrophic = File.join(home, 'CATASTROPHIC_DELIVERY_FAILURE')
        assert_equal(false, test(?e, catastrophic))
        assert(file_contains(errors, /unrecognized option.*--bogus/))
        assert(file_contains(errors, /Failed writing CATASTROPHIC/))
        assert(file_contains(errors, /Errno::ENOENT/))
        assert(file_contains(errors, Regexp.new(Regexp.escape(home))))
      end

      def do_test_no_config_file(config)
        cmd = format("'%s' '%s' -I '%s' %s %s < /dev/null",
                     ruby_program, script, Dir.getwd,
                     rubymail_load_path,
                     config.nil? ? '' : config)
        assert_equal(false, system(cmd))
        assert_equal(75 << 8, $?)
        catastrophic = File.join(home, 'CATASTROPHIC_DELIVERY_FAILURE')
        assert(test(?e, catastrophic))
        assert(file_contains(catastrophic, /Errno::ENOENT/))

        temp = config
        temp ||= '.rdeliver'
        assert(file_contains(catastrophic,
                             Regexp.new(Regexp.escape(File.join(home, temp)))))
      end

      def test_no_dot_rdeliver
        assert_equal(false, system(format("'%s' '%s' -I '%s' %s < /dev/null",
                                          ruby_program, script, Dir.getwd,
                                          rubymail_load_path)))
        assert_equal(75 << 8, $?)
        catastrophic = File.join(home, 'CATASTROPHIC_DELIVERY_FAILURE')
        assert(test(?e, catastrophic))
        assert(file_contains(catastrophic, /Errno::ENOENT/))
        assert(file_contains(catastrophic,
                             Regexp.new(Regexp.escape(File.join(home, '.rdeliver')))))
      end

      def test_no_dot_rdeliver2
        do_test_no_config_file(nil)
      end

      def test_no_config_file
        do_test_no_config_file("my-config")
      end

      def test_successful_deliver
        config_file = scratch_filename('config')
        File.open(config_file, 'w') { |f|
          f.puts <<-EOF
          def main
            agent.save('INBOX')
          end
          EOF
        }

        message = <<-EOF
        From: bob@example.net
        To: sally@example.net
        Subject: test message

        This is a test message
        EOF

        log = scratch_filename('log')
        command = format("'%s' '%s' -I '%s' %s -l '%s' '%s'",
                         ruby_program, script, Dir.getwd,
                         rubymail_load_path, log, config_file)
        IO.popen(command, 'w') { |io|
          message.each_line { |line|
            line = line.sub(/^\s+/, '')
            io.puts(line)
          }
        }

        assert_equal(0, $?)
        assert(test(?e, log))
        inbox = File.join(home, 'INBOX')
        assert(test(?e, log))
        assert(test(?e, inbox))
        assert(file_contains(log, /action.*save to.*INBOX/i))

        # FIXME: need a generic 'test a valid mbox' method
        assert(file_contains(inbox, /^Subject: test message$/))
        assert(file_contains(inbox, /^From .*\d{4}$/))
        assert(file_contains(inbox, /^This is a test message$/))
      end

      def test_deferred_deliver_message
        config_file = scratch_filename('config')
        File.open(config_file, 'w') { |f|
          f.puts <<-EOF
          def main
            agent.defer("Please try again.  Sorry!")
          end
          EOF
        }

        message = ""
        log = scratch_filename('log')
        stdout = scratch_filename('stdout')
        command = format("'%s' '%s' -I '%s' %s -l '%s' '%s' > '%s'",
                         ruby_program, script, Dir.getwd,
                         rubymail_load_path,
                         log, config_file, stdout)
        IO.popen(command, 'w') { }

        assert_equal(RFilter::MTA::EXITCODE_DEFER << 8, $?)
        assert(test(?e, log))
        assert(test(?e, stdout))
        assert(file_contains(log, /action.*defer.*Please try again.  Sorry!/i))
        assert(file_contains(stdout, /^Please try again.  Sorry!$/))
      end

      def test_deferred_deliver_default
        config_file = scratch_filename('config')
        File.open(config_file, 'w') { |f|
          f.puts <<-EOF
          def main
            agent.defer
          end
          EOF
        }

        message = ""
        log = scratch_filename('log')
        stdout = scratch_filename('stdout')
        command = format("'%s' '%s' -I '%s' %s -l '%s' '%s' > '%s'",
                         ruby_program, script, Dir.getwd,
                         rubymail_load_path,
                         log, config_file, stdout)
        IO.popen(command, 'w') { |io|
        }

        assert_equal(RFilter::MTA::EXITCODE_DEFER << 8, $?)
        assert(test(?e, stdout))
        assert(test(?z, stdout))
        assert(test(?e, log))
        assert(file_contains(log, /action.*defer/i))
      end

      def test_rejected_deliver_message
        config = <<-EOF
        def main
          agent.reject("We don't accept SPAM here.")
        end
        EOF

        string_as_file(config, true) { |config_file|
          message = ""
          log = scratch_filename('log')
          stdout = scratch_filename('stdout')
          command = format("'%s' '%s' -I '%s' %s -l '%s' '%s' > '%s'",
                           ruby_program, script, Dir.getwd,
                           rubymail_load_path, log, config_file.path, stdout)
          IO.popen(command, 'w') { |io|
          }

          assert_equal(RFilter::MTA::EXITCODE_REJECT << 8, $?)
          assert(test(?e, log))
          assert(test(?e, stdout))
          assert(file_contains(log,
                               /action.*reject.*We don't accept SPAM here\./i))
          assert(file_contains(stdout, /^We don't accept SPAM here\.$/))
        }
      end

      def test_rejected_deliver_message2
        config = <<-EOF
        def main
          agent.reject
        end
        EOF

        string_as_file(config, true) { |config_file|
          message = ""
          log = scratch_filename('log')
          stdout = scratch_filename('stdout')
          command = format("'%s' '%s' -I '%s' %s -l '%s' '%s' > '%s'",
                           ruby_program, script, Dir.getwd,
                           rubymail_load_path, log, config_file.path, stdout)
          IO.popen(command, 'w') { |io|
          }

          assert_equal(RFilter::MTA::EXITCODE_REJECT << 8, $?)
          assert(test(?e, stdout))
          assert(test(?z, stdout))
          assert(test(?e, log))
          assert(file_contains(log, /action.*reject/i))
        }
      end

    end
  end
end
