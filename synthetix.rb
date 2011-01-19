#
# Synthetix
# A Ruby Toolkit for Synthesizing Website Interaction
#
# This toolkit provides a small DSL for scripting interactions
# with web sites and web services.  It was originally intended
# to perform advanced web server checks for the Nagios service
# monitoring system, but may have other applications.
#
#
# Copyright (c) 2011 James R. Hunt <filefrog@gmail.com>
#

require 'uri'
require 'net/http'
require 'resolv'

class Synthetix
  class << self
    attr_accessor :redirect_loop_limit
    attr_accessor :enable_debugging
  end

  class Check
    def initialize url, &block
      @last  = nil
      @error = nil

      begin
        url = URI.parse(url)
        @http = Net::HTTP.new(Resolv::getaddress(url.host), url.port)

        instance_eval(&block)
      rescue Exception => e
        if e.is_a? SystemExit
          raise e
        else
          critical e.message unless e.is_a? SystemExit
        end
      end
    end

    def get url
      count = ::Synthetix.redirect_loop_limit

      get_without_redirect url
      get_without_redirect @last['location'] while (300..399) === status_code and (count -= 1) > 0
      (@error = (count > 0 ? nil : "redirect loop")).nil?
    end

    def post url, data
      r = Net::HTTP::Post.new url
      r.form_data = data
      @last = @http.request r
    end

    def get_without_redirect url
      @last = @http.get url
    end

    def status_code
      @last.code.to_i
    end

    def body
      @last.body
    end

    def error
      @error || "(no error)"
    end

    def expect *states
      evaluate_expectations true, states
    end

    def expect_not *states
      evaluate_expectations false, states
    end

    def ok msg
      puts "OK: #{msg}"
      exit 0
    end

    def warning msg
      puts "WARN: #{msg}"
      exit 1
    end

    def critical msg
      puts "CRIT: #{msg}"
      exit 2
    end

    def unknown msg
      puts "UNKNOWN: #{msg}"
      exit 3
    end

    protected
    def evaluate_expectations affirm, states
      states.each do |state|
        evaluate_expectation(state, affirm) or return false
      end
      true
    end

    def evaluate_expectation state, affirm = true
        case state
          when Numeric: last_status_code_matches(state)
          when Symbol:  last_status_code_matches(state)
          when String:  !Regexp.new(state).match(body).nil?
          when Regexp:  !state.match(body).nil?
        end == affirm
    end

    def last_status_code_matches code_or_symbol
      case code_or_symbol
        when :info:         (100..199)
        when :ok:           (200..399)
        when :success:      (200..299)
        when :redirect:     (300..399)
        when :error:        (400..599)
        when :client_error: (400..499)
        when :server_error: (500..599)
        else                code_or_symbol
      end === status_code
    end
  end
end

def against url, &block
  ::Synthetix::Check.new(url, &block).ok "Synthetic Transaction Passed"
end
alias :transaction :against

def debug msg
  $stderr.puts msg if ::Synthetix.enable_debugging
end

::Synthetix.redirect_loop_limit = 70
::Synthetix.enable_debugging = false
