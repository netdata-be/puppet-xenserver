require 'irb'
require 'irb/ext/save-history'
require 'irb/completion'
require_relative 'xenapi/xenapi.rb'
require 'yaml'

def xapi
  @xapi ||= begin
    verify    = :verify_none
    xapi_host = 'http://10.12.12.34'
    password  = 'Vasco123.'
    username  = 'root'
    session = XenApi::Client.new(xapi_host, 10, verify)
    session.login_with_password(username, password)
    session
  end
end

ARGV.concat [ "--readline", "--prompt-mode", "simple" ]
IRB.conf[:SAVE_HISTORY] = 1000
IRB.conf[:HISTORY_FILE] = "#{ENV['HOME']}/.irb-save-history"
IRB.start
