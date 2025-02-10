# frozen_string_literal: true

require 'net/http'
require 'json'
require 'date'

def env_has_key(key)
  !ENV[key].nil? && ENV[key] != '' ? ENV[key] : abort("Missing #{key}.")
end

MINUTES_IN_A_DAY = 1440
$username = env_has_key('AC_TESTINIUM_USERNAME')
$password = env_has_key('AC_TESTINIUM_PASSWORD')
$plan_id = env_has_key('AC_TESTINIUM_PLAN_ID')
$ac_max_failure_percentage = (ENV['AC_TESTINIUM_MAX_FAIL_PERCENTAGE'] || 0).to_i
$company_id = env_has_key('AC_TESTINIUM_COMPANY_ID')
$env_file_path = env_has_key('AC_ENV_FILE_PATH')
$each_api_max_retry_count = env_has_key('AC_TESTINIUM_MAX_API_RETRY_COUNT').to_i
timeout = env_has_key('AC_TESTINIUM_TIMEOUT').to_i
date_now = DateTime.now
$end_time = date_now + Rational(timeout, MINUTES_IN_A_DAY)
$time_period = 30

def get_parsed_response(response)
  JSON.parse(response, symbolize_names: true)
rescue JSON::ParserError, TypeError => e
  puts "\nJSON was expected from the response of Testinium API, but the received value is: (#{response})\n. Error Message: #{e}\n"
  exit(1)
end

def calc_percent(numerator, denominator)
  if !(denominator >= 0)
    puts "Invalid numerator or denominator numbers"
    exit(1)
  elsif denominator == 0
    return 0
  else
    return numerator.to_f / denominator.to_f * 100.0
  end
end

def check_timeout()
  puts "Checking timeout..."
  now = DateTime.now

  if(now > $end_time)
    puts 'The component is terminating due to a timeout exceeded.
     If you want to allow more time, please increase the AC_TESTINIUM_TIMEOUT input value.'
    exit(1)
  end
end

def is_count_less_than_max_api_retry(count)
  return count < $each_api_max_retry_count
end

def login()
  puts "Logging in to Testinium..."
  uri = URI.parse('https://account.testinium.com/uaa/oauth/token')
  token = 'dGVzdGluaXVtU3VpdGVUcnVzdGVkQ2xpZW50OnRlc3Rpbml1bVN1aXRlU2VjcmV0S2V5'
  count = 1

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts("Signing in. Number of attempts: #{count}")

    req = Net::HTTP::Post.new(uri.request_uri,
                              { 'Content-Type' => 'application/json', 'Authorization' => "Basic #{token}" })
    req.set_form_data({ 'grant_type' => 'password', 'username' => $username, 'password' => $password })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if (res.kind_of? Net::HTTPSuccess)
      puts('Successfully logged in...')
      return get_parsed_response(res.body)[:access_token]
    elsif (res.kind_of? Net::HTTPUnauthorized)
      puts(get_parsed_response(res.body)[:error_description])
      count += 1
    else
      puts("Error while signing in. Response from server: #{get_parsed_response(res.body)}")
      count += 1
    end
  end
  exit(1)
end

def check_status(access_token)
  count = 1
  uri = URI.parse("https://testinium.io/Testinium.RestApi/api/plans/#{$plan_id}/checkIsRunning")

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    req = Net::HTTP::Get.new(uri.request_uri,
                             { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if (res.kind_of? Net::HTTPSuccess)
      if get_parsed_response(res.body)[:running]
        puts('Plan is still running...')
        sleep($time_period)
      else
        puts('Plan is not running...')
        return
      end
    elsif (res.kind_of? Net::HTTPClientError)
      puts(get_parsed_response(res.body)[:message])
      count += 1
    else
      puts("Error while checking plan status. Response from server: #{get_parsed_response(res.body)}")
      count += 1
    end
  end
  exit(1)
end

def start(access_token)
  count = 1

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts("Starting a new test plan... Number of attempts: #{count}")
    uri = URI.parse("https://testinium.io/Testinium.RestApi/api/plans/#{$plan_id}/run")
    req = Net::HTTP::Get.new(uri.request_uri,
                             { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if (res.kind_of? Net::HTTPSuccess)
      puts('Plan started successfully...')
      return get_parsed_response(res.body)[:execution_id]
    elsif (res.kind_of? Net::HTTPClientError)
      puts(get_parsed_response(res.body)[:message])
      count += 1
    else
      puts("Error while starting Plan. Response from server: #{get_parsed_response(res.body)}")
      count += 1
    end
  end
  exit(1)
end

def get_report(execution_id, access_token)
  count = 1

  while is_count_less_than_max_api_retry(count) do
    check_timeout()
    puts("Starting to get the report...Number of attempts: #{count}")
    uri = URI.parse("https://testinium.io/Testinium.RestApi/api/executions/#{execution_id}")
    req = Net::HTTP::Get.new(uri.request_uri,
                             { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => "#{$company_id}" })
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if (res.kind_of? Net::HTTPSuccess)
      puts('Report received successfully...')

      data = get_parsed_response(res.body)
      result_summary = data[:result_summary]
      result_failure_summary = result_summary[:FAILURE] || 0
      result_error_summary = result_summary[:ERROR] || 0
      result_success_summary = result_summary[:SUCCESS] || 0
      puts "Test result summary: #{result_summary}"
      total_summary = result_failure_summary + result_error_summary + result_success_summary

      open("#{$env_file_path}", 'a') { |f|
        f.puts "AC_TESTINIUM_RESULT_FAILURE_SUMMARY=#{result_failure_summary}"
        f.puts "AC_TESTINIUM_RESULT_ERROR_SUMMARY=#{result_error_summary}"
        f.puts "AC_TESTINIUM_RESULT_SUCCESS_SUMMARY=#{result_success_summary}"
      }

      if $ac_max_failure_percentage > 0 && result_failure_summary > 0
        failure_percentage = calc_percent(result_failure_summary, total_summary)
        max_failure_percentage = calc_percent($ac_max_failure_percentage, 100)

        if max_failure_percentage <= failure_percentage || !result_summary[:ERROR].nil?
          puts "The number of failures in the plan exceeded the maximum rate. The process is being stopped. #{data[:test_result_status_counts]}"
          exit(1)
        else
          puts("Number of failures is below the maximum rate. Process continues. #{data[:test_result_status_counts]}")
        end
      else
        warn_message = "To calculate the failure rate, the following values must be greater than 0:" \
          "\nAC_TESTINIUM_MAX_FAIL_PERCENTAGE: #{$ac_max_failure_percentage}" \
          "\nTestinium Result Failure Summary: #{result_failure_summary}"
        puts warn_message
      end

      return
    elsif (res.kind_of? Net::HTTPClientError)
      puts(get_parsed_response(res.body)[:message])
      count += 1
    else
      puts("Error while starting Plan. Response from server: #{get_parsed_response(res.body)}")
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