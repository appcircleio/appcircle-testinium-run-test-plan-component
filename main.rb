# frozen_string_literal: true

require 'net/http'
require 'json'
require 'date'
require 'colored'

def env_has_key(key)
  !ENV[key].nil? && ENV[key] != '' ? ENV[key] : abort("Missing #{key}.".red)
end

def get_env_variable(key)
  return (ENV[key] == nil || ENV[key] == "") ? nil : ENV[key]
end

MINUTES_IN_A_DAY = 1440
$username = env_has_key('AC_TESTINIUM_USERNAME')
$password = env_has_key('AC_TESTINIUM_PASSWORD')
$plan_id = env_has_key('AC_TESTINIUM_PLAN_ID')
$ac_max_failure_percentage = (get_env_variable('AC_TESTINIUM_MAX_FAIL_PERCENTAGE') || 0).to_i
$company_id = get_env_variable('AC_TESTINIUM_COMPANY_ID')
$env_file_path = env_has_key('AC_ENV_FILE_PATH')
$each_api_max_retry_count = env_has_key('AC_TESTINIUM_MAX_API_RETRY_COUNT').to_i
timeout = env_has_key('AC_TESTINIUM_TIMEOUT').to_i
date_now = DateTime.now
$end_time = date_now + Rational(timeout, MINUTES_IN_A_DAY)
$time_period = 30

def get_parsed_response(response)
  JSON.parse(response, symbolize_names: true)
rescue JSON::ParserError, TypeError => e
  puts "\nJSON expected but received: #{response}".red
  puts "Error Message: #{e}".red
  exit(1)
end

def calc_percent(numerator, denominator)
  if !(denominator >= 0)
    puts "Invalid numerator or denominator numbers".red
    exit(1)
  elsif denominator == 0
    return 0
  else
    return numerator.to_f / denominator.to_f * 100.0
  end
end

def check_timeout()
  puts "Checking timeout...".yellow
  now = DateTime.now

  if now > $end_time
    puts "Timeout exceeded! Increase AC_TESTINIUM_TIMEOUT value.".red
    exit(1)
  end
end

def is_count_less_than_max_api_retry(count)
  count < $each_api_max_retry_count
end

def login()
  puts "Logging in to Testinium...".yellow
  uri = URI.parse('https://account.testinium.com/uaa/oauth/token')
  token = 'dGVzdGluaXVtU3VpdGVUcnVzdGVkQ2xpZW50OnRlc3Rpbml1bVN1aXRlU2VjcmV0S2V5'
  count = 1

  while is_count_less_than_max_api_retry(count)
    check_timeout()
    puts "Signing in. Attempt: #{count}".blue

    req = Net::HTTP::Post.new(uri.request_uri, { 'Content-Type' => 'application/json', 'Authorization' => "Basic #{token}" })
    req.set_form_data({ 'grant_type' => 'password', 'username' => $username, 'password' => $password })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    if res.is_a?(Net::HTTPSuccess)
      puts "Successfully logged in...".green
      return get_parsed_response(res.body)[:access_token]
    elsif res.is_a?(Net::HTTPUnauthorized)
      puts get_parsed_response(res.body)[:error_description].red
      count += 1
    else
      puts "Login error: #{get_parsed_response(res.body)}".red
      count += 1
    end
  end
  exit(1)
end

def check_status(access_token)
  count = 1
  uri = URI.parse("https://testinium.io/Testinium.RestApi/api/plans/#{$plan_id}/checkIsRunning")

  while is_count_less_than_max_api_retry(count)
    check_timeout()
    req = Net::HTTP::Get.new(uri.request_uri, { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => $company_id })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    if res.is_a?(Net::HTTPSuccess)
      if get_parsed_response(res.body)[:running]
        puts "Plan is still running...".yellow
        sleep($time_period)
      else
        puts "Plan is not running.".green
        return
      end
    elsif res.is_a?(Net::HTTPClientError)
      puts get_parsed_response(res.body)[:message].red
      count += 1
    else
      puts "Error checking plan status: #{get_parsed_response(res.body)}".red
      count += 1
    end
  end
  exit(1)
end

def start(access_token)
  count = 1

  while is_count_less_than_max_api_retry(count)
    check_timeout()
    puts "Starting test plan... Attempt: #{count}".blue
    uri = URI.parse("https://testinium.io/Testinium.RestApi/api/plans/#{$plan_id}/run")
    req = Net::HTTP::Get.new(uri.request_uri, { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => $company_id })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    if res.is_a?(Net::HTTPSuccess)
      puts "Plan started successfully.".green
      return get_parsed_response(res.body)[:execution_id]
    elsif res.is_a?(Net::HTTPClientError)
      puts get_parsed_response(res.body)[:message].red
      count += 1
    else
      puts "Error starting plan: #{get_parsed_response(res.body)}".red
      count += 1
    end
  end
  exit(1)
end

def get_report(execution_id, access_token)
  count = 1

  while is_count_less_than_max_api_retry(count)
    check_timeout()
    puts "Fetching test report... Attempt: #{count}".blue
    uri = URI.parse("https://testinium.io/Testinium.RestApi/api/executions/#{execution_id}")
    req = Net::HTTP::Get.new(uri.request_uri, { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => $company_id })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    if res.is_a?(Net::HTTPSuccess)
      puts "Test report received.".green

      data = get_parsed_response(res.body)
      result_summary = data[:result_summary]
      result_failure_summary = result_summary[:FAILURE] || 0
      result_error_summary = result_summary[:ERROR] || 0
      result_success_summary = result_summary[:SUCCESS] || 0

      puts "Test result summary: #{result_summary}".yellow

      open($env_file_path, 'a') do |f|
        f.puts "AC_TESTINIUM_RESULT_FAILURE_SUMMARY=#{result_failure_summary}"
        f.puts "AC_TESTINIUM_RESULT_ERROR_SUMMARY=#{result_error_summary}"
        f.puts "AC_TESTINIUM_RESULT_SUCCESS_SUMMARY=#{result_success_summary}"
      end

      if $ac_max_failure_percentage > 0 && result_failure_summary > 0
        failure_percentage = calc_percent(result_failure_summary, result_failure_summary + result_success_summary)
        max_failure_percentage = calc_percent($ac_max_failure_percentage, 100)

        if max_failure_percentage <= failure_percentage || !result_summary[:ERROR].nil?
          puts "Failure rate exceeded! Stopping execution.".red
          exit(1)
        else
          puts "Failure rate within limits. Continuing...".green
        end
      end

      return
    elsif res.is_a?(Net::HTTPClientError)
      puts get_parsed_response(res.body)[:message].red
      count += 1
    else
      puts "Error fetching report: #{get_parsed_response(res.body)}".red
      count += 1
    end
  end
  exit(1)
end

access_token = login()
check_status(access_token)
execution_id = start(access_token)
check_status(access_token)
get_report(execution_id, access_token)