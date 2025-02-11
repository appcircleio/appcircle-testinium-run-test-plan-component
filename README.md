# Appcircle _Testinium Run Test Plan_ component

Execute your test plans with Testinium as part of your Appcircle pipeline. This component provides seamless automation, enabling efficient test execution after application uploads using the **Testinium App Upload** step.

## Required Inputs

- `AC_TESTINIUM_USERNAME`: Testinium username.
- `AC_TESTINIUM_PASSWORD`: Testinium password.
- `AC_TESTINIUM_PLAN_ID`: Testinium plan ID.
- `AC_TESTINIUM_COMPANY_ID`: Testinium company ID.
- `AC_TESTINIUM_TIMEOUT`: Testinium plan timeout in minutes.
- `AC_TESTINIUM_MAX_API_RETRY_COUNT`: Determine max repetition in case of Testinium platform congestion or API errors.

## Optional Inputs

- `AC_TESTINIUM_MAX_FAIL_PERCENTAGE`: Maximum failure percentage limit to interrupt workflow. It must be in the range 1-100.

## Output Variables

- `AC_TESTINIUM_RESULT_FAILURE_SUMMARY`: Total number of failures in test results.
- `AC_TESTINIUM_RESULT_ERROR_SUMMARY`: Total number of errors in test results.
- `AC_TESTINIUM_RESULT_SUCCESS_SUMMARY`: Total number of successes in test results.