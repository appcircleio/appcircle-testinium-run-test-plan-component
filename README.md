# Appcircle _Testinium Run Test Plan_ component

Execute your test plans with Testinium as part of your Appcircle pipeline. This component provides seamless automation, enabling efficient test execution after application uploads using the **Testinium App Upload** step.

## Required Inputs

- `AC_TESTINIUM_USERNAME`: Testinium username.
- `AC_TESTINIUM_PASSWORD`: Testinium password.
- `AC_TESTINIUM_PLAN_ID`: Testinium plan ID.
- `AC_TESTINIUM_COMPANY_ID`: Testinium company ID.
- `AC_TESTINIUM_TIMEOUT`: Testinium plan timeout in minutes.
- `AC_TESTINIUM_MAX_API_RETRY_COUNT`: Determine max repetition in case of Testinium platform congestion or API errors.
- `AC_TESTINIUM_UPLOADED_APP_ID`: The unique identifier for the application uploaded to Testinium. This ID is generated after the **Testinium App Upload** step.
- `AC_TESTINIUM_APP_OS`: The operating system of the uploaded application, either iOS or Android. This value is determined after the **Testinium App Upload** step.

## Optional Inputs

- `AC_TESTINIUM_ENTERPRISE_BASE_URL`: The base URL for Testinium Enterprise. This is required if you are using Testinium Enterprise. Only for Testinium cloud users, this input is not mandatory.
- `AC_TESTINIUM_MAX_FAIL_PERCENTAGE`: Maximum failure percentage limit to interrupt workflow. It must be in the range 1-100.

## Output Variables

- `AC_TESTINIUM_RESULT_FAILURE_SUMMARY`: Total number of failures in test results.
- `AC_TESTINIUM_RESULT_ERROR_SUMMARY`: Total number of errors in test results.
- `AC_TESTINIUM_RESULT_SUCCESS_SUMMARY`: Total number of successes in test results.