#!/usr/bin/env ruby
#--
#   Copyright (C) 2002 Matt Armstrong.  All rights reserved.
#
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

# The function daemon is covered by the copyright below, and was
# fetched from
# http://orange.kame.net/dev/cvsweb.cgi/kame/kame/kame/dtcp/dtcps.rb?rev=1.6
#
# Copyright (C) 1999 WIDE Project.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of the project nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE PROJECT AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE PROJECT OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
def daemon(nochdir, noclose)
  pid = fork
  if pid == -1
    return -1
  elsif pid != nil
    exit 0
  end

  Process.setsid()

  Dir.chdir('/') if (nochdir == 0)
  if noclose == 0
    devnull = open("/dev/null", "r+")
    $stdin.reopen(devnull)
    $stdout.reopen(devnull)
    p = IO::pipe
    pid = fork
    if pid == -1
      $stderr.reopen(devnull)
    elsif pid == nil
      p[1].close
      STDIN.reopen(p[0])
      p[0].close
    else
      p[0].close
      $stderr.reopen(p[1])
      p[1].close
    end
  end
  return 0
end

$queue = "Maildir"
$log = '.rfilter.log'

require 'rfilter/delivery_agent'

# The Deliver class used by the bin/rdeliver.rb script to provide
# a place for the user's delivery script to run.  The user's
# delivery script executes in the context of this class, so
# methods defined with +def+ do not pollute the global namespace.
# The user is expected to define a #main method that will be
# called to deliver the mail.
#
# See also bin/rdeliver.rb
class Deliver
  def initialize(agent) # :nodoc:
    @__MAIL_DELIVERY_AGENT__ = agent
  end
  # Return the RFilter::DeliveryAgent object for the current message.
  # This is all you need to retrieve, modify, and deliver the message.
  def agent
    @__MAIL_DELIVERY_AGENT__
  end
  # This method is called by bin/filter.rb after the Deliver object is
  # instantiated.  A default implementation that merely defers the
  # delivery is provided, but the user is expected to replace this
  # with a version that delivers the mail to the proper location.
  def main
    agent.defer('no deliver method specified in configuration file')
  end
end

def queue_file_time(name)
  base = File.basename(name)
  first, = base.split('.')
  Integer(first)
end

def process_queue
  files = Dir[File.join($queue, 'new') + '/*'].sort { |a, b|
    queue_file_time(a) <=> queue_file_time(b)
  }
  files.each { |queue_file_name|
    begin
      File.open(queue_file_name) { |queue_file|
	RFilter::DeliveryAgent.process(queue_file, $log) { |agent|
	  Deliver.new(agent).main
	}
      }
    rescue RFilter::DeliveryAgent::DeliverySuccess
      File::unlink(queue_file_name)
    rescue RFilter::DeliveryAgent::DeliveryReject
      # FIXME: for now, reject just drops the message on the floor
      File::unlink(queue_file_name)
    rescue RFilter::DeliveryAgent::DeliveryComplete
      # FIXME: truly defer somehow
    end
  }
end

def wait_for_more(max_minutes)
  max_seconds = max_minutes * 60
  GC.start
  if sleep(max_seconds + 1) >= max_seconds
    # If we waited this long and there was no more mail, exit to free
    # up the system resources.
    exit
  end
end

def main

  # Read the .rdeliver file, which fills in the Deliver class.
  $config = '.rdeliver'

  # FIXME: make errors logged from this a lot more clear.
  eval(IO.readlines($config, nil)[0].untaint,
       Deliver.module_eval('binding()'),
       $config)

  begin
    toucher_thread = Thread.start {
      loop {
	now = Time.now
	File.utime(now, now, File.join("Maildir", ".filter.lock"))
	sleep(60)
      }
    }
    loop {
      process_queue
      sleep(15)
    }
  ensure
    Thread::kill(toucher_thread) if toucher_thread
    File::delete($lock_file_name)
  end
end

lockfile_name = File.join("Maildir", ".filter")
if system('lockfile-create', '--retry', '1', lockfile_name)
  begin
    main
  ensure
    system('lockfile-remove', lockfile_name)
  end
end

