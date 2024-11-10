#!/usr/bin/env bash

USER_AGENT="ACME.sh/1.0"

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
function dns_firstdomains_add {
  local record_name=$1
  local txt_value=$2

  FIRSTDOMAINS_Username="${FIRSTDOMAINS_Username:-$(_readaccountconf_mutable FIRSTDOMAINS_Username)}"
  FIRSTDOMAINS_Password="${FIRSTDOMAINS_Password:-$(_readaccountconf_mutable FIRSTDOMAINS_Password)}"
  if [ -z "$FIRSTDOMAINS_Username" ] || [ -z "$FIRSTDOMAINS_Password" ]; then
      FIRSTDOMAINS_Username=""
      FIRSTDOMAINS_Password=""
      _err "Please specify Username and Password"
      return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable FIRSTDOMAINS_Username "$FIRSTDOMAINS_Username"
  _saveaccountconf_mutable FIRSTDOMAINS_Password "$FIRSTDOMAINS_Password"

  # Authenticate and obtain session cookie
  web_session=$(get_first_domains_login "$FIRSTDOMAINS_Username" "$FIRSTDOMAINS_Password")
  
  # Determine root name
  root_name=$(get_first_domains_root_name "$record_name" "$web_session")
  
  # Add DNS record
  add_first_domains_record "$record_name" "$txt_value" "$root_name" "$web_session"
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
function dns_firstdomains_rm {
  local record_name=$1
  local txt_value=$2

  FIRSTDOMAINS_Username="${FIRSTDOMAINS_Username:-$(_readaccountconf_mutable FIRSTDOMAINS_Username)}"
  FIRSTDOMAINS_Password="${FIRSTDOMAINS_Password:-$(_readaccountconf_mutable FIRSTDOMAINS_Password)}"
  if [ -z "$FIRSTDOMAINS_Username" ] || [ -z "$FIRSTDOMAINS_Password" ]; then
      FIRSTDOMAINS_Username=""
      FIRSTDOMAINS_Password=""
      _err "Please specify Username and Password"
      return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable FIRSTDOMAINS_Username "$FIRSTDOMAINS_Username"
  _saveaccountconf_mutable FIRSTDOMAINS_Password "$FIRSTDOMAINS_Password"

  # Authenticate and obtain session cookie
  web_session=$(get_first_domains_login "$FIRSTDOMAINS_Username" "$FIRSTDOMAINS_Password")
  
  # Determine root name
  root_name=$(get_first_domains_root_name "$record_name" "$web_session")
  
  # Find and remove record
  record_id=$(get_first_domains_record_id "$txt_value" "$root_name" "$web_session")
  remove_first_domains_record "$record_id" "$root_name" "$web_session"
}

# Helper to log in and obtain session
function get_first_domains_login {
  local username=$1
  local password=$2

  # Use curl to login
  response=$(curl -s -X POST \
    -H "User-Agent: $USER_AGENT" \
    -d "action=login&account_login=$username&account_password=$password" \
    -c - "https://1stdomains.nz/client/login.php")
  
  # Extract session ID from cookie
  echo "$response" | grep -oP '1stsid\s+\K[^;]+'
}

function add_first_domains_record {
  local record_name=$1
  local txt_value=$2
  local root_name=$3
  local session_id=$4

  curl -s -X POST \
    -H "User-Agent: $USER_AGENT" \
    -H "Referer: https://1stdomains.nz/client/account_manager.php" \
    -d "library=zone_manager&action=add_record&domain_name=$root_name&host_name=$record_name&record_type=TXT&record_content=$txt_value" \
    -b "1stsid=$session_id" \
    "https://1stdomains.nz/client/json_wrapper.php"
}

function remove_first_domains_record {
  local record_id=$1
  local root_name=$2
  local session_id=$3

  curl -s -X POST \
    -H "User-Agent: $USER_AGENT" \
    -H "Referer: https://1stdomains.nz/client/account_manager.php" \
    -d "library=zone_manager&action=del_records&domain_name=$root_name&checked_records=$record_id" \
    -b "1stsid=$session_id" \
    "https://1stdomains.nz/client/json_wrapper.php"
}

function get_first_domains_record_id {
  local txt_value=$1
  local root_name=$2
  local session_id=$3

  response=$(curl -s -X POST \
    -H "User-Agent: $USER_AGENT" \
    -H "Referer: https://1stdomains.nz/client/account_manager.php" \
    -d "library=zone_manager&action=load_records&domain_name=$root_name" \
    -b "1stsid=$session_id" \
    "https://1stdomains.nz/client/json_wrapper.php")
  
  # Parse JSON response to find record ID by matching the txt_value
  echo "$response" | jq -r --arg txt_value "$txt_value" '.rows[] | select(.cell[3] == $txt_value) | .cell[0]'
}

function get_first_domains_root_name {
  local record_name=$1
  local session_id=$2

  IFS='.' read -ra parts <<< "$record_name"
  current_line=""
  for (( i=$((${#parts[@]}-1)); i>=0; i-- )); do
    if [ -n "$current_line" ]; then
      current_line="${parts[i]}.$current_line"
    else
      current_line="${parts[i]}"
    fi

    if [ "$i" -eq "$((${#parts[@]}-1))" ]; then
      continue
    fi

    response=$(curl -s -X POST \
      -H "User-Agent: $USER_AGENT" \
      -H "Referer: https://1stdomains.nz/client/account_manager.php" \
      -d "library=zone_manager&action=load_records&domain_name=$current_line" \
      -b "1stsid=$session_id" \
      "https://1stdomains.nz/client/json_wrapper.php")
    
    if ! echo "$response" | jq -e '.errors' > /dev/null; then
      echo "$current_line"
      return
    fi
  done
}
