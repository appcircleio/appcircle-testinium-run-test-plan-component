# frozen_string_literal: true

require 'net/http'
require 'json'
require 'date'
require 'colored'

def env_has_key(key)
  ENV[key].nil? || ENV[key].empty? ? abort("Missing #{key}.".red) : ENV[key]
end

def get_env_variable(key)
  ENV[key].nil? || ENV[key].empty? ? nil : ENV[key]
end

MINUTES_IN_A_DAY = 1440
$username = env_has_key('AC_TESTINIUM_USERNAME')
$password = env_has_key('AC_TESTINIUM_PASSWORD')
$plan_id = env_has_key('AC_TESTINIUM_PLAN_ID')
$company_id = get_env_variable('AC_TESTINIUM_COMPANY_ID')
$ac_max_failure_percentage = (get_env_variable('AC_TESTINIUM_MAX_FAIL_PERCENTAGE') || 0).to_i
$env_file_path = env_has_key('AC_ENV_FILE_PATH')
$output_dir = env_has_key('AC_OUTPUT_DIR')
$each_api_max_retry_count = env_has_key('AC_TESTINIUM_MAX_API_RETRY_COUNT').to_i
$end_time = DateTime.now + Rational(env_has_key('AC_TESTINIUM_TIMEOUT').to_i, MINUTES_IN_A_DAY)
$check_api_time_period = 30
$cloud_base_url = "https://testinium.io/"
$ent_base_url = get_env_variable('AC_TESTINIUM_ENTERPRISE_BASE_URL')

def get_base_url
  URI.join($ent_base_url || $cloud_base_url, "Testinium.RestApi/api").to_s
end

def get_parsed_response(response)
  JSON.parse(response, symbolize_names: true)
rescue JSON::ParserError, TypeError => e
  puts "\nJSON expected but received: #{response}".red
  abort "Error Message: #{e}".red
end

def calc_percent(numerator, denominator)
  if !(denominator >= 0)
    abort "Invalid numerator or denominator numbers".red
  elsif denominator == 0
    return 0
  else
    return numerator.to_f / denominator.to_f * 100.0
  end
end

def check_timeout
  if DateTime.now > $end_time
    abort "Timeout exceeded! Increase AC_TESTINIUM_TIMEOUT if needed.".red
  end
end

def retry_request(max_retries)
  count = 1
  while count <= max_retries
    check_timeout
    yield(count)
    count += 1
  end
  abort "Max retries exceeded.".red
end

def send_request(method, url, headers, body = nil)
  use_ssl = get_base_url.match?(/^https/)
  uri = URI.parse(url)
  req = case method.upcase
        when 'GET'
          Net::HTTP::Get.new(uri.request_uri, headers)
        when 'POST'
          post_req = Net::HTTP::Post.new(uri.request_uri, headers)
          post_req.set_form_data(body) if body
          post_req
        when 'PUT'
          put_req = Net::HTTP::Put.new(uri.request_uri, headers)
          put_req.body = body.to_json if body
          put_req
        else
          raise "Unsupported HTTP method: #{method}"
        end

  Net::HTTP.start(uri.hostname, uri.port, use_ssl: $use_ssl) { |http| http.request(req) }
end

def handle_api_response(res, action, parsed = true)
  case res
  when Net::HTTPSuccess
    puts "#{action.capitalize} successful.".green
    return parsed ? get_parsed_response(res.body) : nil
  when Net::HTTPUnauthorized
    puts "Authorization error while #{action}: #{get_parsed_response(res.body)[:error_description]}".red
  when Net::HTTPClientError
    puts "Client error while #{action}: #{get_parsed_response(res.body)[:message]}".red
  else
    puts "Unexpected error while #{action}: #{get_parsed_response(res.body)}".red
  end
  return nil
end

def login
  puts "Logging in to Testinium...".yellow
  base_url = $ent_base_url ? get_base_url.sub("/api", "") : "https://account.testinium.com/uaa"

  # Testinium's login API uses a public generic token for authentication. More details:  
  # Cloud: https://testinium.gitbook.io/testinium/apis/auth/login  
  # Enterprise: https://testinium.gitbook.io/testinium-enterprise/apis/auth/login 
  token = $ent_base_url ? "Y2xpZW50MTpjbGllbnQx" : "dGVzdGluaXVtU3VpdGVUcnVzdGVkQ2xpZW50OnRlc3Rpbml1bVN1aXRlU2VjcmV0S2V5"
  url = "#{base_url}/oauth/token"
  headers = { 'Content-Type' => 'application/x-www-form-urlencoded', 'Authorization' => "Basic #{token}" }
  body = { 'grant_type' => 'password', 'username' => $username, 'password' => $password }

  retry_request($each_api_max_retry_count) do
    res = send_request('POST', url, headers, body)
    parsed_response = handle_api_response(res, "logging")
    return parsed_response[:access_token] if parsed_response
  end
end

def check_status(access_token)
  puts "Checking plan status...".blue
  url = "#{get_base_url}/plans/#{$plan_id}/checkIsRunning"
  headers = { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => $company_id }

  retry_request($each_api_max_retry_count) do
    res = send_request('GET', url, headers)
    parsed_response = handle_api_response(res, "checking the plan")
    next unless parsed_response 
    
    if parsed_response[:running] == false
      puts "Plan is not running.".green
      return
    else
      puts "Plan is still running...".yellow
    end
    
    sleep($check_api_time_period)
  end
end

def select_app(access_token)
  $uploaded_app_id = env_has_key('AC_TESTINIUM_UPLOADED_APP_ID')
  $app_os = env_has_key('AC_TESTINIUM_APP_OS')
  puts "Starting select #{$app_os} app (ID=#{$uploaded_app_id}) for the test plan...".blue
  url = "#{get_base_url}/plans/#{$plan_id}/set#{$app_os}MobileApp/#{$uploaded_app_id}"
  headers = { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}" }

  retry_request($each_api_max_retry_count) do
    res = send_request('PUT', url, headers)
    parsed_response = handle_api_response(res, "selecting the application")
    return parsed_response if parsed_response
  end
end

def start(access_token)
  puts "Starting test plan...".blue
  url = "#{get_base_url}/plans/#{$plan_id}/run"
  headers = { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => $company_id }

  retry_request($each_api_max_retry_count) do
    res = send_request('GET', url, headers)
    parsed_response = handle_api_response(res, "starting test plan")
    return parsed_response[:execution_id] if parsed_response
  end
end

def get_report(execution_id, access_token)
  puts "Fetching test report...".blue
  base_url = get_base_url + ($ent_base_url ? "/testExecutions" : "/executions")
  url = "#{base_url}/#{execution_id}"
  headers = { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}", 'current-company-id' => $company_id }
  report_file_path = "#{$output_dir}/test_report_#{execution_id}.json"

  retry_request($each_api_max_retry_count) do
    res = send_request('GET', url, headers)
    parsed_response = handle_api_response(res, "fetching test report")
    return parsed_response if parsed_response == nil

    File.write(report_file_path, JSON.pretty_generate(parsed_response))
    result_summary = parsed_response[:result_summary]
    puts "Test result summary: #{result_summary}".yellow
    result_failure_summary = result_summary[:FAILURE] || 0
    result_error_summary = result_summary[:ERROR] || 0
    result_success_summary = result_summary[:SUCCESS] || 0

    open($env_file_path, 'a') do |f|
      f.puts "AC_TESTINIUM_RESULT_FAILURE_SUMMARY=#{result_failure_summary}"
      f.puts "AC_TESTINIUM_RESULT_ERROR_SUMMARY=#{result_error_summary}"
      f.puts "AC_TESTINIUM_RESULT_SUCCESS_SUMMARY=#{result_success_summary}"
      f.puts "AC_TESTINIUM_TEST_REPORT=#{report_file_path}"
    end

    puts "Test report has been successfully saved.".green
    puts "📊 Test plan results:".green
    puts "   ❌ Errors: #{result_error_summary}".red
    puts "   ⚠️ Failures: #{result_failure_summary}".yellow
    puts "   ✅ Successes: #{result_success_summary}".green
    
    abort "❗ Test execution stopped due to errors!" if result_error_summary > 0

    if $ac_max_failure_percentage > 0 && result_failure_summary > 0
      failure_percentage = calc_percent(result_failure_summary, result_failure_summary + result_success_summary)
      max_failure_percentage = calc_percent($ac_max_failure_percentage, 100)

      if max_failure_percentage <= failure_percentage
        abort "Failure rate exceeded! Stopping execution.".red
      else
        puts "Failure rate within limits. Continuing...".green
      end
    end
    return
  end
end

access_token = login()
check_status(access_token)
select_app(access_token) if $ent_base_url
execution_id = start(access_token)
check_status(access_token)
get_report(execution_id, access_token)
