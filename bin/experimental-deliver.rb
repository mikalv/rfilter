#!/usr/bin/env ruby
#--
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
#++
# This script delivers a mail message taken from stdin to a mail
# queue, and then starts the mail filter program if it isn't already
# running.
#
# === Usage
#
# deliver.rb is invoked from the command line using:
#
#   % deliver.rb <options>
#
# Options are:
#
# <tt>--load-path</tt>::     Prepend the given directory to ruby's
#                            load path.
#
# <tt>--log</tt> <i>filename</i>::   Log to the given <i>filename</i>.  If no
#                                    log is specified, no logging occurs.
#
# <tt>--home</tt> <i>directory</i>::  Specify the home <i>directory</i>.
#                                     rdeliver will change to this directory
#                                     before reading and writing any files.
#                                     The home directory defaults to
#                                     the value of the +HOME+ or +LOGDIR+
#                                     environment variable.
# === Installation
#
# Assuming you have the RubyMail mail classes installed, you typically
# have to put something like this in your .forward file:
#
#    |"/usr/local/bin/deliver.rb --log /home/you/.rlog"
#
# This will call rdeliver for each new message you get, and log to
# <tt>/home/you/.rlog</tt>.
#
# === Catastrophic Errors
#
# The deliver.rb script is very careful with errors.  If there is any
# problem, it logs the error to the log file you specify.  But if you
# do not specify a log file, or the error occurs before the log file
# is opened, a record of the error is placed in a file called
# CATASTROPHIC_DELIVERY_FAILURE in the home directory.  If that fails,
# the error information is printed to the standard output in the hopes
# that it will be part of a bounce message.  In all cases, the exit
# code 75 is returned, which tells the MTA to re-try the delivery
# again.

def print_exception(file, exception) # :nodoc:
  file.puts("Exception:\n    " +
	    exception.inspect + "\n")
  file.puts "Backtrace:\n"
  exception.backtrace.each { |line|
    file.puts "    " + line + "\n"
  }
end

def filter_pid(queue_dir)
  pid = nil

  begin
    File::open("Maildir/.filterpid") { |file|
      if Time.now - file.stat.mtime < (60 * 60 * 4)
	pid_str = file.gets.chomp.strip
	if pid_str =~ /^\d+/
	  pid = Integer(pid_str)
	end
      end
    }
  rescue Errno::ENOENT
  end
  return pid
end

def run_filter
  # FIXME: this is useful only for me.  Hmm...
  exec("/home/matt/pkg/bin/ruby-cvs",
       '-I', '/home/matt/bk/live/rubyfilter',
       '-I', '/home/matt/bk/live/rubymail',
       "/home/matt/bk/live/rubyfilter/bin/filter.rb")
end


# Try to get to home dir, in preparation for possibly writing
# CATASTROPHIC_DELIVERY_FAILURE
not_in_home_dir_exception = nil
begin
  Dir.chdir
rescue Exception
  not_in_home_dir_exception = $!
end

begin
  $SAFE = 1
  require 'getoptlong'

  parser = GetoptLong.new\
  (['--load-path', '-I', GetoptLong::REQUIRED_ARGUMENT],
   ['--log', '-l', GetoptLong::REQUIRED_ARGUMENT],
   ['--home', '-h', GetoptLong::REQUIRED_ARGUMENT])
  parser.quiet = true
  log = nil
  parser.each_option do |name, arg|
    case name
    when '--home'
      Dir.chdir(arg.untaint)
      not_in_home_dir_exception = nil
    when '--log'
      log = arg.untaint
    when '--load-path'
      $LOAD_PATH.unshift(arg.untaint)
    else
      raise "don't know about argument #{name}"
    end
  end

  raise "extra arguments passed to #{$0}: #{ARGV.inspect}" unless ARGV.empty?

  require 'rfilter/deliver'
  include RFilter::Deliver
  queue = "Maildir"
  deliver_maildir(queue, $stdin)

  fork {
    Process.setsid()
    File.umask(077)
    devnull = open('/dev/null', 'r+')
#    errors = open('/tmp/errors', 'w')
    $stdin.reopen(devnull)
#    $stdout.reopen(errors)
#    $stderr.reopen(errors)
    $stdout.reopen(devnull)
    $stderr.reopen(devnull)
    run_filter
    exit!
  }
  exit(0)

rescue Exception => exception
  if exception.class <= SystemExit
    raise exception		# normal exit
  else
    # Be nice and stick the last delivery failure due to a catastrophic
    # situation in home/CATASTROPHIC_DELIVERY_FAILURE
    begin
      unless not_in_home_dir_exception.nil?
	raise not_in_home_dir_exception
      end
      File.open("CATASTROPHIC_DELIVERY_FAILURE", "w") { |file|
	print_exception(file, exception)
        file.puts "LOAD_PATH"
        file.puts $LOAD_PATH.inspect
      }
    rescue Exception => another_exception
      # In the event that the above doesn't happen, we write the error
      # to stdout and hope the mailer includes it in the bounce that
      # will eventually occur.
      print_exception(STDOUT, exception)
      puts "Failed writing CATASTROPHIC_DELIVERY_FAILURE because:"
      print_exception(STDOUT, another_exception)
    ensure
      exit 75			# EX_TMPFAIL
    end
  end
end

