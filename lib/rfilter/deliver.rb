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

module RFilter

  # This is a module containing methods that know how deliver to
  # various kinds of message folder types.
  module Deliver

    @@mail_deliver_maildir_count = 0

    SYNC_IF_NO_FSYNC = RUBY_VERSION >= "1.7" ? 0 : File::SYNC

    class DeliveryError < StandardError
    end
    class NotAFile < DeliveryError
    end
    class NotAMailbox < DeliveryError
    end
    class LockingError < DeliveryError
    end

    # Deliver +message+ to an mbox +filename+.
    #
    # The +each+ method on +message+ is used to get each line of the
    # message.  If the first line of the message is not an mbox
    # <tt>From_</tt> header, a fake one will be generated.
    #
    # The file named by +filename+ is opened for append, and +flock+
    # locking is used to prevent other processes from modifying the
    # file during delivery.  No ".lock" style locking is performed.
    # If that is desired, it should be performed before calling this
    # method.
    #
    # Returns the name of the file delivered to, or raises an
    # exception if delivery failed.
    def deliver_mbox(filename, message)
      return filename if filename == '/dev/null'
      File.open(filename,
                File::APPEND|File::WRONLY|File::CREAT|SYNC_IF_NO_FSYNC,
		0600) { |f|
        max = 5
        max.times { |i|
          break if f.flock(File::LOCK_EX | File::LOCK_NB)
          raise LockingError, "Timeout locking mailbox." if i == max - 1
          sleep(1)
        }
        st = f.lstat
        unless st.file?
          raise NotAFile,
            "Can not deliver to #{filename}, not a regular file."
        end
        begin
          # Ignore SIGXFSZ, since we want to get the Errno::EFBIG
          # exception when the file is too big.
          old_handler = trap('XFSZ', 'IGNORE') || 'DEFAULT'
          write_to_mbox(f, message)
          begin
            f.fsync
          rescue NameError
            # NameError happens with older versions of Ruby that have
            # no File#fsync
            f.flush
          end
        rescue Exception => e
          begin
            begin
              f.flush
            rescue Exception
            end
            f.truncate(st.size)
          ensure
            raise e
          end
        ensure
          if old_handler
            trap('XFSZ', old_handler)
          end
        end
	f.flock(File::LOCK_UN)
      }
      filename
    end
    module_function :deliver_mbox

    # Write to an already opened mbox file.  This low level function
    # just takes care of escaping From_ lines in the message.  See
    # deliver_mbox for a more robust version.
    def write_to_mbox(output_io, message)
      first = true
      message.each { |line|
        if first
          first = false
          if line !~ /^From .*\d$/
            from = "From foo@bar  " + Time.now.asctime + "\n"
            output_io << from
          end
        elsif line =~ /^From /
          output_io << '>'
        end
        output_io << line
        output_io << "\n" unless line[-1] == ?\n
      }
      output_io << "\n"
    end
    module_function :write_to_mbox

    # Deliver +message+ to a pipe.
    #
    # The supplied +command+ is run in a sub process, and
    # <tt>message.each</tt> is used to get each line of the message
    # and write it to the pipe.
    #
    # This method captures the <tt>Errno::EPIPE</tt> and ignores it,
    # since this exception can be generated when the command exits
    # before the entire message is written to it (which may or may not
    # be an error).
    #
    # The caller can (and should!) examine <tt>$?</tt> to see the exit
    # status of the pipe command.
    def deliver_pipe(command, message)
      begin
	IO.popen(command, "w") { |io|
	  message.each { |line|
	    io << line
	    io << "\n" unless line[-1] == ?\n
	  }
	}
      rescue Errno::EPIPE
	# Just ignore.
      end
    end
    module_function :deliver_pipe

    # Deliver +message+ to a filter and provide the io stream for
    # reading the filtered content to the supplied block.
    #
    # The supplied +command+ is run in a sub process, and
    # <tt>message.each</tt> is used to get each line of the message
    # and write it to the filter.
    #
    # The block passed to the function is run with IO objects for the
    # stdout of the child process.
    #
    # Returns the exit status of the child process.
    def deliver_filter(message, *command)
      begin
        to_r, to_w = IO.pipe
        from_r, from_w = IO.pipe
        if pid = fork
          # parent
          to_r.close
          from_w.close
          writer = Thread::new {
            message.each { |line|
              to_w << line
              to_w << "\n" unless line[-1] == ?\n
            }
            to_w.close
          }
          yield from_r
        else
          # child
          begin
            to_w.close
            from_r.close
            STDIN.reopen(to_r)
            to_r.close
            STDOUT.reopen(from_w)
            from_w.close
            exec(*command)
          ensure
            exit!
          end
        end
      ensure
        writer.kill if writer and writer.alive?
        [ to_r, to_w, from_r, from_w ].each { |io|
          if io && !io.closed?
            begin
              io.close
            rescue Errno::EPIPE
            end
          end
        }
      end
      Process.waitpid2(pid, 0)[1]
    end
    module_function :deliver_filter

    # Delivery +message+ to a Maildir.
    #
    # See http://cr.yp.to/proto/maildir.html for a description of the
    # maildir mailbox format.  Its primary advantage is that it
    # requires no locks -- delivery and access to the mailbox can
    # occur at the same time.
    #
    # The +each+ method on +message+ is used to get each line of the
    # message.  If the first line of the message is an mbox
    # <tt>From_</tt> line, it is discarded.
    #
    # The filename of the successfully delivered message is returned.
    # Will raise exceptions on any kind of error.
    #
    # This method will attempt to create the Maildir if it does not
    # exist.
    def deliver_maildir(dir, message)
      require 'socket'

      # First, make the required directories
      new = File.join(dir, 'new')
      tmp = File.join(dir, 'tmp')
      [ dir, new, tmp, File.join(dir, 'cur') ].each { |d|
        begin
          Dir.mkdir(d, 0700)
        rescue Errno::EEXIST
          raise unless FileTest::directory?(d)
        end
      }

      sequence = @@mail_deliver_maildir_count
      @@mail_deliver_maildir_count = @@mail_deliver_maildir_count.next
      tmp_name = nil
      new_name = nil
      hostname = Socket::gethostname.gsub(/[^\w]/, '_').untaint
      pid = Process::pid
      3.times { |i|
        now = Time::now
        name = sprintf("%d.M%XP%dQ%d.%s",
                       Time::now.tv_sec, Time::now.tv_usec,
                       pid, sequence, hostname)
        tmp_name = File.join(tmp, name)
        new_name = File.join(new, name)
        begin
          File::stat(tmp_name)
        rescue Errno::ENOENT
          break
        rescue Exception
          raise if i == 2
        end
        raise "Too many tmp file conflicts." if i == 2
        sleep(2)
      }

      begin
        File.open(tmp_name,
                  File::CREAT|File::EXCL|File::WRONLY|SYNC_IF_NO_FSYNC,
                  0600) { |f|
          # Write the message to the file
          first = true
          message.each { |line|
            if first
              first = false
              next if line =~ /From /
            end
            f << line
            f << "\n" unless line[-1] == ?\n
          }
          f.fsync if defined? f.fsync
        }
        File.link(tmp_name, new_name)
      ensure
        begin
          File.delete(tmp_name)
        rescue Errno::ENOENT
        end
      end
      new_name
    end
    module_function :deliver_maildir

  end
end
