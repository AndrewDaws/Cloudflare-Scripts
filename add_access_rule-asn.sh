#!/bin/bash

abort_script() {
  # Declare local variables
  local script_name

  # Initialize local variables
  script_name="$(basename "${0}")"

  # Print error message
  echo "Aborting ${script_name}"
  # Check for error messages
  if [[ -n "${*}" ]]; then
    # Treat each input parameter as a separate error line
    for error_msg in "${@}"
    do
      echo "  ${error_msg}"
    done
  fi

  # Exit script with return code
  exit 1
}

check_connectivity() {
  # Declare local variables
  local test_ip
  local test_count

  # Initialize local variables
  test_count="1"
  if [[ -n "${1}" ]]; then
    test_ip="${1}"
  else
    test_ip="8.8.8.8"
  fi

  # Test connectivity
  if ping -c "${test_count}" "${test_ip}" &> /dev/null; then
    return 0
  else
    return 1
  fi
 }

# Download access rules
download_access_rules() {
  # Declare local variables
  local input_file
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

  # Check internet connectivity
  if ! check_connectivity; then
    # Error checking internet connectivity
    abort_script "Cloudflare access rules download error" "No internet connection!"
  fi

  # Check if Cloudflare domain is valid and accessible
  if ! check_connectivity "${cloudflare_api_url}"; then
    # Error checking Cloudflare connectivity
    abort_script "Cloudflare access rules download error" "No connection to Cloudflare!"
  fi

  rm -f "${output_file}"
  while [[ "${current_page}" -eq "0" ]] || [[ "${current_page}" -lt "${current_total_pages}" && "${current_count}" -lt "${current_total_count}" ]]; do
    # Increment page counter
    ((current_page+=1))

    # Download current access rules}
    rm -f "${output_file}-response"
    if ! curl \
      --silent \
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
    response_page="$( sed -n '/^  "result_info": {$/,/^  }$/{//!p;}' "${output_file}-response" | grep -o -P "\"page\": [0-9]+" | grep -o -P '[0-9]+' )"
    response_per_page="$( sed -n '/^  "result_info": {$/,/^  }$/{//!p;}' "${output_file}-response" | grep -o -P "\"per_page\": [0-9]+" | grep -o -P '[0-9]+' )"
    response_count="$( sed -n '/^  "result_info": {$/,/^  }$/{//!p;}' "${output_file}-response" | grep -o -P "\"count\": [0-9]+" | grep -o -P '[0-9]+' )"
    response_total_count="$( sed -n '/^  "result_info": {$/,/^  }$/{//!p;}' "${output_file}-response" | grep -o -P "\"total_count\": [0-9]+" | grep -o -P '[0-9]+' )"
    response_total_pages="$( sed -n '/^  "result_info": {$/,/^  }$/{//!p;}' "${output_file}-response" | grep -o -P "\"total_pages\": [0-9]+" | grep -o -P '[0-9]+' )"

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
        abort_script "Cloudflare access rules processing error" "Response and expected page values do not match!"
      fi

      # Check if response per page equals current per page value
      if [[ "${response_per_page}" -ne "${current_per_page}" ]]; then
        # Error per page mismatch
        rm -f "${output_file}"
        rm -f "${output_file}-response"
        abort_script "Cloudflare access rules processing error" "Response and expected per page values do not match!"
      fi

      # Check if response total count equals current total count value
      if [[ "${response_total_count}" -ne "${current_total_count}" ]]; then
        # Error total count mismatch
        rm -f "${output_file}"
        rm -f "${output_file}-response"
        abort_script "Cloudflare access rules processing error" "Response and expected total count do not match!"
      fi

      # Check if response total pages equals current total pages value
      if [[ "${response_total_pages}" -ne "${current_total_pages}" ]]; then
        # Error total pages mismatch
        rm -f "${output_file}"
        rm -f "${output_file}-response"
        abort_script "Cloudflare access rules processing error" "Response and expected total pages do not match!"
      fi
    fi

    # Check if actual count equals response count value
    if [[ "$( grep -o "\"target\": \"asn\"" "${output_file}-response" | wc -l )" -ne "${response_count}" ]]; then
      # Error page overflow
      rm -f "${output_file}"
      rm -f "${output_file}-response"
      abort_script "Cloudflare access rules processing error" "Actual and response count do not match!"
    fi

    # Store responses
    current_page="${response_page}"
    current_per_page="${response_per_page}"
    current_count="$(( ${current_count} + ${response_count} ))"
    current_total_count="${response_total_count}"
    current_total_pages="${response_total_pages}"

    # Check if current count is greater than current total count value
    if [[ "${current_count}" -gt "${current_total_count}" ]]; then
      # Error count overflow
      rm -f "${output_file}"
      rm -f "${output_file}-response"
      abort_script "Cloudflare access rules processing error" "Expected count is greater than expected total!"
    fi

    # Check if current page is greater than current total pages value
    if [[ "${current_page}" -gt "${current_total_pages}" ]]; then
      # Error page overflow
      rm -f "${output_file}"
      rm -f "${output_file}-response"
      abort_script "Cloudflare access rules processing error" "Expected page is greater than expected total!"
    fi

    # Merge response data into single output file
    sed -n '/^  "result": \[$/,/^  \],$/{//!p;}' "${output_file}-response" >> "${output_file}"
    rm -f "${output_file}-response"

    # Check if parsed response info is not missing
    if [[ ! -f "${output_file}" ]]; then
      # Error missing response info
      rm -f "${output_file}"
      abort_script "Cloudflare access rules processing error" "Access rules file does not exist!"
    fi

    # Check if parsed response info is not empty
    if [[ ! -s "${output_file}" ]]; then
      # Error empty response info
      rm -f "${output_file}"
      abort_script "Cloudflare access rules processing error" "Access rules file is empty!"
    fi

    # Check if actual count equals response count value
    if [[ "$( grep -o "\"target\": \"asn\"" "${output_file}" | wc -l )" -ne "${current_count}" ]]; then
      # Error page overflow
      rm -f "${output_file}"
      abort_script "Cloudflare access rules processing error" "Actual and expected count do not match!"
    fi
  done
}

# Update entity names with correct names
add_access_rules() {
  # Declare local variables
  local input_file
  local cloudflare_account_id
  local cloudflare_api_key
  local cloudflare_config_file
  local cloudflare_api_url
  local cloudflare_access_file

  # Initialize local variables
  input_file="${*}"
  cloudflare_account_id=""
  cloudflare_api_key=""
  cloudflare_config_file="${PWD}/cloudflare.ini"
  cloudflare_api_url="api.cloudflare.com"
  cloudflare_access_file="${PWD}/cloudflare_access_rules.txt"

  # Check if input file variable is set
  if [[ -z "${input_file}" ]]; then
    # Error finding input file
    abort_script "Cloudflare input file error" "Input file not provided!"
  fi

  # Check if input file is not missing
  if [[ ! -f "${input_file}" ]]; then
    # Error missing input file
    abort_script "Cloudflare input file error" "Input file does not exist!"
  fi

  # Check if input file is not empty
  if [[ ! -s "${input_file}" ]]; then
    # Error empty input file
    abort_script "Cloudflare input file error" "Input file is empty!"
  fi

  # Download current access rules
  download_access_rules "${cloudflare_access_file}"

  # Find current Cloudflare license key from config file
  if [[ -f "${cloudflare_config_file}" ]]; then
    # Found Cloudflare config file
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

  # Check internet connectivity
  if ! check_connectivity; then
    # Error checking internet connectivity
    abort_script "Cloudflare access rules upload error" "No internet connection!"
  fi

  # Check if Cloudflare domain is valid and accessible
  if ! check_connectivity "${cloudflare_api_url}"; then
    # Error checking Cloudflare connectivity
    abort_script "Cloudflare access rules upload error" "No connection to Cloudflare!"
  fi

  # Access rules file exists and is not empty
  while read currentLine || [ -n "${currentLine}" ]; do
    # Load ASN from current line
    currentASN="$( echo "${currentLine}" | grep -o -P '^[^,]+' | grep -o -P '[0-9]+' )"

    # Check if current line contains an ASN
    if [[ -n "${currentASN}" ]]; then
      # Check if Cloudflare access rules contain the ASN
      if ! grep "\"value\": \"AS${currentASN}\"" "${cloudflare_access_file}" &> /dev/null; then
        # Load entity from current line
        currentEntity="$( echo "${currentLine}" | grep -o -P '^\"?[0-9]+\"?,\s*\K\"?.+\"?$' | sed -e 's/"//g' )"

        # Add missing ASN to Cloudflare access rules
        if ! curl \
          --silent \
          -X POST "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/firewall/access_rules/rules" \
          -H "Authorization: Bearer ${CLOUDFLARE_API_KEY}" \
          -H "Content-Type: application/json" \
          --data '{"mode":"block","configuration":{"target":"asn","value":"AS'"${currentASN}"'"},"notes":"Script: '"${currentEntity}"'"}' \
          | grep "\"success\": true" \
          &> /dev/null; then
          # Error adding missing access rule
          echo "Error: Failed to add Cloudflare access rule AS${currentASN} = ${currentEntity}!"
          rm -f "${cloudflare_access_file}"
          exit 1
        else
          # Successfully added access rule
          echo "Added Cloudflare access rule AS${currentASN} = ${currentEntity}"
        fi
      fi
    fi
  done < "${input_file}"

  # Cleanup temp files
  rm -f "${cloudflare_access_file}"
}

# Main function
main() {
  # Declare local variables
  local input_file

  # Initialize local variables
  input_file="${*}"

  # Check if input file variable is set
  if [[ -z "${input_file}" ]]; then
    # Error finding input file
    abort_script "Cloudflare input file error" "Input file not provided!"
  fi

  # Check if input file is not missing
  if [[ ! -f "${input_file}" ]]; then
    # Error missing input file
    abort_script "Cloudflare input file error" "Input file does not exist!"
  fi

  # Check if input file is not empty
  if [[ ! -s "${input_file}" ]]; then
    # Error empty input file
    abort_script "Cloudflare input file error" "Input file is empty!"
  fi

  # Add access rules
  add_access_rules "${input_file}"
}

# Begin script
main "${*}"

# Exit script with no return code
exit 0
