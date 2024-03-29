#!/bin/bash

exit_script() {
  # Declare local variables
  local return_code

  # Initialize local variables
  return_code="1"

  # Input parameter provided
  if [[ -n "${1}" ]]; then
    # Check against valid return codes
    if [[ "${1}" -eq 0 || "${1}" -eq 1 ]]; then
      # Overwrite return code
      return_code="${1}"
    fi
  fi

  # Exit script with return code
  exit "${return_code}"
}

script_filename() {
  # Declare local variables
  local output_filename

  # Initialize local variables
  output_filename="$(basename "${0}")"

  # Return script filename
  echo "${output_filename}"
}

abort_script() {
  # Declare local variables
  local calling_function

  # Initialize local variables
  calling_function="${FUNCNAME[1]}"

  # Replace calling function name when helper function used
  if [[ "${calling_function}" == "abort_*" ]]; then
    calling_function="${FUNCNAME[2]}"
  fi

  # Print error message
  echo ""
  print_stage "Aborting execution of $(script_filename)"
  echo "Error in function ${calling_function}:"

  # Check for error messages
  if [[ -n "${*}" ]]; then
    # Treat each input parameter as a separate line
    for error_msg in "${@}"; do
      echo "  ${error_msg}"
    done
  fi

  # Exit script with error
  exit_script "1"
}

is_installed() {
  # Declare local variables
  local input_application

  # Initialize local variables
  input_application="${1}"

  # Returns 0 if application is installed or error if it is not
  if which "${input_application}" | grep -o "${input_application}" >/dev/null; then
    return 0
  else
    return 1
  fi
}

check_connectivity() {
  # Declare local variables
  local test_address
  local test_count
  local test_timeout
  local return_code

  # Initialize local variables
  if [[ -n "${1}" ]]; then
    test_address="${1}"
  else
    test_address="8.8.8.8"
  fi
  test_count="1"
  test_timeout="5"
  return_code="-1"

  # Test connectivity with ping
  # Check if ping is installed
  if is_installed ping; then
    if ping \
      -c "${test_count}" \
      "${test_address}" \
      &>/dev/null; then
      return_code="0"
    else
      return_code="1"
    fi
  fi

  # Test connectivity with wget if not previously successful
  if [[ "${return_code}" -ne 0 ]]; then
    # Check if wget is installed
    if is_installed wget; then
      if wget \
        --quiet \
        --timeout="${test_timeout}" \
        --tries="${test_count}" \
        --spider \
        "${test_address}" \
        &>/dev/null; then
        return_code="0"
      else
        return_code="1"
      fi
    fi
  fi

  # Test connectivity with curl if not previously successful
  if [[ "${return_code}" -ne 0 ]]; then
    # Check if curl is installed
    if is_installed curl; then
      if curl \
        --silent \
        --connect-timeout "${test_timeout}" \
        --max-time "${test_timeout}" \
        "${test_address}" \
        &>/dev/null; then
        return_code="0"
      else
        return_code="1"
      fi
    fi
  fi

  # Return 0 if connected, 1 if not connected, or -1 if no tools installed
  return "${return_code}"
}

# Download access rules
download_access_rules() {
  # Declare local variables
  local cloudflare_account_id
  local cloudflare_api_key
  local cloudflare_config_file
  local cloudflare_api_url
  local output_file
  local current_page
  local current_per_page
  local current_count
  local current_total_count
  local current_total_pages
  local response_page
  local response_per_page
  local response_count
  local response_total_count
  local response_total_pages

  # Initialize local variables
  output_file="${*}"
  cloudflare_account_id=""
  cloudflare_api_key=""
  cloudflare_config_file="${PWD}/cloudflare.ini"
  cloudflare_api_url="api.cloudflare.com"
  current_page="0"
  current_per_page="1000"
  current_count="0"
  current_total_count="0"
  current_total_pages="0"

  # Check if output file variable is set
  if [[ -z "${output_file}" ]]; then
    # Error finding output file
    abort_script "Cloudflare output file error" "Output file not provided!"
  fi

  # Find current Cloudflare license key from config file
  if [[ -f "${cloudflare_config_file}" ]]; then
    # Found Cloudflare config file
    # shellcheck disable=SC1090
    source "${cloudflare_config_file}"
  fi

  # Find current Cloudflare account ID from environment
  if [[ -n "${CLOUDFLARE_ACCOUNT_ID}" ]]; then
    # Found Cloudflare account ID variable from config file, or in environment
    cloudflare_account_id="${CLOUDFLARE_ACCOUNT_ID}"
  fi

  # Check if Cloudflare account ID variable is set
  if [[ -z "${cloudflare_account_id}" ]]; then
    # Error finding Cloudflare account ID
    abort_script "Cloudflare access rules download error" "Failed to find account ID!"
  fi

  # Find current Cloudflare API key from environment
  if [[ -n "${CLOUDFLARE_API_KEY}" ]]; then
    # Found Cloudflare API key variable from config file, or in environment
    cloudflare_api_key="${CLOUDFLARE_API_KEY}"
  fi

  # Check if Cloudflare API key variable is set
  if [[ -z "${cloudflare_api_key}" ]]; then
    # Error finding Cloudflare API key
    abort_script "Cloudflare access rules download error" "Failed to find API key!"
  fi

  # Check if Cloudflare domain is valid and accessible
  if ! check_connectivity "${cloudflare_api_url}"; then
    # Error checking Cloudflare connectivity
    abort_script "Cloudflare access rules download error" "No connection to Cloudflare!"
  fi

  rm -f "${output_file}"
  while [[ "${current_page}" -eq "0" ]] || [[ "${current_page}" -lt "${current_total_pages}" && "${current_count}" -lt "${current_total_count}" ]]; do
    # Increment page counter
    ((current_page += 1))

    # Download current access rules}
    rm -f "${output_file}-response"
    if ! curl \
      --silent \
      --connect-timeout 5 \
      --max-time 5 \
      -X GET "https://${cloudflare_api_url}/client/v4/accounts/${cloudflare_account_id}/firewall/access_rules/rules?page=${current_page}&per_page=${current_per_page}&mode=block&configuration.target=asn" \
      -H "Authorization: Bearer ${cloudflare_api_key}" \
      -H "Content-Type: application/json" \
      --output "${output_file}-response"; then

      # Error downloading access rules
      rm -f "${output_file}"
      rm -f "${output_file}-response"
      abort_script "Cloudflare access rules download error" "Failed to download!"
    fi

    # Check if downloaded access rules is not empty or missing
    if [[ ! -f "${output_file}-response" ]]; then
      # Error empty or missing access rules
      rm -f "${output_file}"
      rm -f "${output_file}-response"
      abort_script "Cloudflare access rules download error" "Download file does not exist!"
    fi

    # Check if downloaded access rules is not empty or missing
    if [[ ! -s "${output_file}-response" ]]; then
      # Error empty or missing access rules
      rm -f "${output_file}"
      rm -f "${output_file}-response"
      abort_script "Cloudflare access rules download error" "Download file is empty!"
    fi

    # Check if downloaded access rules return success
    if ! grep -q "\"success\": true" "${output_file}-response"; then
      # Error invalid Cloudflare database
      rm -f "${output_file}"
      rm -f "${output_file}-response"
      abort_script "Cloudflare access rules download error" "Did not return success!"
    fi

    # Clear response info variables
    response_page=""
    response_per_page=""
    response_count=""
    response_total_count=""
    response_total_pages=""

    # # Parse response info into variables
    response_page="$(sed -n '/^  "result_info": {$/,/^  }$/{//!p;}' "${output_file}-response" | grep -o -P "\"page\": [0-9]+" | grep -o -P '[0-9]+')"
    response_per_page="$(sed -n '/^  "result_info": {$/,/^  }$/{//!p;}' "${output_file}-response" | grep -o -P "\"per_page\": [0-9]+" | grep -o -P '[0-9]+')"
    response_count="$(sed -n '/^  "result_info": {$/,/^  }$/{//!p;}' "${output_file}-response" | grep -o -P "\"count\": [0-9]+" | grep -o -P '[0-9]+')"
    response_total_count="$(sed -n '/^  "result_info": {$/,/^  }$/{//!p;}' "${output_file}-response" | grep -o -P "\"total_count\": [0-9]+" | grep -o -P '[0-9]+')"
    response_total_pages="$(sed -n '/^  "result_info": {$/,/^  }$/{//!p;}' "${output_file}-response" | grep -o -P "\"total_pages\": [0-9]+" | grep -o -P '[0-9]+')"

    # Check if response page variable is set
    if [[ -z "${response_page}" ]]; then
      # Error finding response page
      rm -f "${output_file}"
      rm -f "${output_file}-response"
      abort_script "Cloudflare access rules processing error" "Failed to find response page!"
    fi

    # Check if response per page variable is set
    if [[ -z "${response_per_page}" ]]; then
      # Error finding response per page
      rm -f "${output_file}"
      rm -f "${output_file}-response"
      abort_script "Cloudflare access rules processing error" "Failed to find response per page!"
    fi

    # Check if response count variable is set
    if [[ -z "${response_count}" ]]; then
      # Error finding response count
      rm -f "${output_file}"
      rm -f "${output_file}-response"
      abort_script "Cloudflare access rules processing error" "Failed to find response count!"
    fi

    # Check if response total count variable is set
    if [[ -z "${response_total_count}" ]]; then
      # Error finding response total count
      rm -f "${output_file}"
      rm -f "${output_file}-response"
      abort_script "Cloudflare access rules processing error" "Failed to find response total count!"
    fi

    # Check if response total pages variable is set
    if [[ -z "${response_total_pages}" ]]; then
      # Error finding response total pages
      rm -f "${output_file}"
      rm -f "${output_file}-response"
      abort_script "Cloudflare access rules processing error" "Failed to find response total pages!"
    fi

    # Check responses info against previous responses if not the first loop
    if [[ "${current_page}" -ne "1" ]]; then
      # Check if response page equals current page value
      if [[ "${response_page}" -ne "${current_page}" ]]; then
        # Error page mismatch
        rm -f "${output_file}"
        rm -f "${output_file}-response"
        abort_script "Cloudflare access rules processing error" "Response [${response_page}] and expected [${current_page}] page values do not match!"
      fi

      # Check if response per page equals current per page value
      if [[ "${response_per_page}" -ne "${current_per_page}" ]]; then
        # Error per page mismatch
        rm -f "${output_file}"
        rm -f "${output_file}-response"
        abort_script "Cloudflare access rules processing error" "Response [${response_per_page}] and expected [${current_per_page}] per page values do not match!"
      fi

      # Check if response total count equals current total count value
      if [[ "${response_total_count}" -ne "${current_total_count}" ]]; then
        # Error total count mismatch
        rm -f "${output_file}"
        rm -f "${output_file}-response"
        abort_script "Cloudflare access rules processing error" "Response [${response_total_count}] and expected [${current_total_count}] total count do not match!"
      fi

      # Check if response total pages equals current total pages value
      if [[ "${response_total_pages}" -ne "${current_total_pages}" ]]; then
        # Error total pages mismatch
        rm -f "${output_file}"
        rm -f "${output_file}-response"
        abort_script "Cloudflare access rules processing error" "Response [${response_total_pages}] and expected [${current_total_pages}] total pages do not match!"
      fi
    fi

    # Check if actual count equals response count value
    if [[ "$(grep -o "\"target\": \"asn\"" "${output_file}-response" | wc -l)" -ne "${response_count}" ]]; then
      # Error page overflow
      rm -f "${output_file}"
      rm -f "${output_file}-response"
      abort_script "Cloudflare access rules processing error" "Actual and response count do not match!"
    fi

    # Store responses
    current_page="${response_page}"
    current_per_page="${response_per_page}"
    current_count="$((${current_count} + ${response_count}))"
    current_total_count="${response_total_count}"
    current_total_pages="${response_total_pages}"

    # Check if current count is greater than current total count value
    if [[ "${current_count}" -gt "${current_total_count}" ]]; then
      # Error count overflow
      rm -f "${output_file}"
      rm -f "${output_file}-response"
      abort_script "Cloudflare access rules processing error" "Expected [${current_count}] count is greater than expected [${current_total_count}] total!"
    fi

    # Check if current page is greater than current total pages value
    if [[ "${current_page}" -gt "${current_total_pages}" ]]; then
      # Check if current total pages value is zero
      if [[ "${current_total_pages}" -ne "0" ]]; then
        # Check if current page value is one
        if [[ "${current_page}" -ne "1" ]]; then
          # Error page overflow
          rm -f "${output_file}"
          rm -f "${output_file}-response"
          abort_script "Cloudflare access rules processing error" "Expected [${current_page}] page is greater than expected [${current_total_pages}] total!"
        fi
      fi
    fi

    # Merge response data into single output file
    sed -n '/^  "result": \[$/,/^  \],$/{//!p;}' "${output_file}-response" >>"${output_file}"
    rm -f "${output_file}-response"

    # Check if parsed response info is not missing
    if [[ ! -f "${output_file}" ]]; then
      # Error missing response info
      rm -f "${output_file}"
      abort_script "Cloudflare access rules processing error" "Access rules file does not exist!"
    fi

    # Check if response total count value is zero
    if [[ "${response_total_count}" -ne "0" ]]; then
      # Check if parsed response info is not empty
      if [[ ! -s "${output_file}" ]]; then
        # Error empty response info
        rm -f "${output_file}"
        abort_script "Cloudflare access rules processing error" "Access rules file is empty!"
      fi
    fi

    # Check if actual count equals response count value
    if [[ "$(grep -o "\"target\": \"asn\"" "${output_file}" | wc -l)" -ne "${current_count}" ]]; then
      # Error page overflow
      rm -f "${output_file}"
      abort_script "Cloudflare access rules processing error" "Actual and expected count do not match!"
    fi
  done
}

# Update entity names with correct names
remove_access_rules() {
  # Declare local variables
  local cloudflare_account_id
  local cloudflare_api_key
  local cloudflare_config_file
  local cloudflare_api_url
  local cloudflare_access_file
  local id_list
  local asn_list

  # Initialize local variables
  cloudflare_account_id=""
  cloudflare_api_key=""
  cloudflare_config_file="${PWD}/cloudflare.ini"
  cloudflare_api_url="api.cloudflare.com"
  cloudflare_access_file="${PWD}/cloudflare_access_rules.txt"
  id_list=()
  asn_list=()

  # Print header
  echo "------------------------------------------------------------------------"
  echo "   Removing Cloudflare Access Rules"
  echo "------------------------------------------------------------------------"
  echo "Preparing..."

  # Download current access rules
  download_access_rules "${cloudflare_access_file}"

  # Find current Cloudflare license key from config file
  if [[ -f "${cloudflare_config_file}" ]]; then
    # Found Cloudflare config file
    # shellcheck disable=SC1090
    source "${cloudflare_config_file}"
  fi

  # Find current Cloudflare account ID from environment
  if [[ -n "${CLOUDFLARE_ACCOUNT_ID}" ]]; then
    # Found Cloudflare account ID variable from config file, or in environment
    cloudflare_account_id="${CLOUDFLARE_ACCOUNT_ID}"
  fi

  # Check if Cloudflare account ID variable is set
  if [[ -z "${cloudflare_account_id}" ]]; then
    # Error finding Cloudflare account ID
    abort_script "Cloudflare access rules upload error" "Failed to find account ID!"
  fi

  # Find current Cloudflare API key from environment
  if [[ -n "${CLOUDFLARE_API_KEY}" ]]; then
    # Found Cloudflare API key variable from config file, or in environment
    cloudflare_api_key="${CLOUDFLARE_API_KEY}"
  fi

  # Check if Cloudflare API key variable is set
  if [[ -z "${cloudflare_api_key}" ]]; then
    # Error finding Cloudflare API key
    abort_script "Cloudflare access rules upload error" "Failed to find API key!"
  fi

  # Check if Cloudflare domain is valid and accessible
  if ! check_connectivity "${cloudflare_api_url}"; then
    # Error checking Cloudflare connectivity
    abort_script "Cloudflare access rules upload error" "No connection to Cloudflare!"
  fi

  # Parse access rules file for rule IDs and store in array
  # shellcheck disable=SC2207
  id_list+=(
    $(grep --extended-regexp '"id":|"target": "asn",' "${cloudflare_access_file}" |
      grep --before-context=1 '"target": "asn",' |
      grep '"id":' |
      cut --delimiter=\" --fields=4)
  )

  # Parse access rules file for rule ASNs and store in array
  # shellcheck disable=SC2207
  asn_list+=(
    $(grep --extended-regexp '"target": "asn",|"value": "AS' "${cloudflare_access_file}" |
      grep --after-context=1 '"target": "asn",' |
      grep '"value": "AS' |
      cut --delimiter=\" --fields=4)
  )

  # Cleanup temp files
  rm -f "${cloudflare_access_file}"

  # Loop through ID list
  for id_index in "${!id_list[@]}"; do
    # Current index not empty
    if [[ -n "${id_list[${id_index}]}" ]]; then
      # Remove existing rule
      echo "[$((id_index + 1))/${#id_list[@]}] Removing rule ${id_list[${id_index}]} {${asn_list[${id_index}]}}"
      if ! curl \
        --silent \
        --connect-timeout 5 \
        --max-time 5 \
        -X DELETE "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/firewall/access_rules/rules/${id_list[${id_index}]}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_KEY}" \
        -H "Content-Type: application/json" |
        grep "\"success\": true" \
          &>/dev/null; then
        # Error removing existing rule
        echo "Error: Failed to remove rule ${id_list[${id_index}]} {${asn_list[${id_index}]}}!"
        exit 1
      fi
    fi
  done
}

# Main function
main() {
  # Remove access rules
  remove_access_rules
}

# Begin script
main "${*}"

# Exit script with no return code
exit 0
