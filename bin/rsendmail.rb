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
require 'rmail/parser'
require 'rmail/address'
require 'rmail/serialize'

def syslog(str)
  system('logger', '-p', 'mail.info', '-t', 'rsendmail', str.to_s)
end

extract_recipients = false
sender = nil
full_name = nil
single_dot_ends = true
end_of_options = false
recipients = []
while not ARGV.empty?
  arg = ARGV.shift
  if ! recipients.empty? || arg =~ /\A[^-]/ || end_of_options
    recipients.push(arg)
  else
    case arg
    when '-t'
      extract_recipients = true
    when '-f'
      sender = ARGV.shift
    when '-F'
      full_name = ARGV.shift
    when '-oi'
      single_dot_ends = false
    when '--'
      end_of_options = true
    else
      $stderr.puts("rsendmail: invalid option -- #{arg}")
      exit 1
    end
  end
end

# FIXME: parsing messages should be external to the RMail::Message
# class.  For example, we should differentiate here between -oi and
# not -oi.
message = RMail::Parser.new.parse($stdin)

def get_recipients(message, field_name, list)
  unless message.header[field_name].nil?
    RMail::Address.parse(message.header[field_name]).each do |address|
      # FIXME: need an "smtpaddress" method
      list.push(address.address)
    end
  end
end

if extract_recipients
  get_recipients(message, 'to',  recipients)
  get_recipients(message, 'cc',  recipients)
  get_recipients(message, 'bcc', recipients)
end

# FIXME: put this into some kind of library

# FIXME: simplify verp recipients?

# FIXME: share with .rdeliver
def with_db(name)
  require 'gdbm'
  begin
    db = nil
    begin
      db = GDBM::open(File.join("/home/matt/.rfilter/var", name), 0600)
    rescue Errno::EWOULDBLOCK
      # FIXME: only wait so long, then defer
      sleep(2)
      retry
    end
    yield db
  ensure
    db.close unless db.nil?
  end
end

# FIXME: share with .rdeliver
def record_string_in_db(db, address)
  record = db[address]
  count = record.split(/:/)[1] unless record.nil?
  count ||= '0'
  db[address] = Time.now.strftime("%Y%m%d") + ':' + count.succ
end

with_db('sent-recipient') do |db|
  dup = {}
  recipients.each do |r|
    address = r.downcase
    record_string_in_db(db, address) unless dup.key?(address)
    dup[address] ||= 1
  end
end

with_db "sent-subjects" do |db|
  if subject = message.header['subject']
    subject = subject.strip.downcase
    record_string_in_db(db, subject)
  end
end

with_db "sent-msgid" do |db|
  if msgid = message.header['message-id']
    msgid = msgid.strip.downcase
    record_string_in_db(db, msgid)
  end
end


# FIXME: delete any bcc headers

# FIXME: should be able to generate a default From: header
#raise 'no from header' if message.header['from'].nil?

# FIXME: more error checking here

IO.popen('-', 'w') do |child|
  if child.nil?
    # FIXME: instead of 'address' need a way to output the address for
    # SMTP purposes.
    command = ['/usr/sbin/sendmail', '-oi']
    command.concat(['-F', full_name]) if full_name
    command.concat(['-f', sender]) if sender
    command.concat(recipients)
    #syslog("args ouggoing: " + command.inspect)
    exec(*command)
  else
    RMail::Serialize.new(child).serialize(message)
  end
end
