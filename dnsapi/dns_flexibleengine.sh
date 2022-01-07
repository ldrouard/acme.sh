#!/usr/bin/env sh

# This is the Orange Flexible Engine (Public Cloud Orange Business Services)
# API wrapper for acme.sh
#
# More information :
#   * Product : https://www.orange-business.com/en/products/flexible-engine
#   * API : https://developer.orange.com/apis/flexible-engine/getting-started
#   * Regions and Endpoints : https://docs.prod-cloud-ocb.orange-business.com/en-us/endpoint/index.html
#
# Derivated from DNS Challenge Cloudflare
#   * https://github.com/acmesh-official/acme.sh/blob/master/dnsapi/dns_cf.sh


# User Token from Flexible Engine
# HINT : May be you should put this VAR in ARGS instead modify this script :
#        FE_Token="--SECRET--" ./acmesh/acme.sh ....
# HELP : https://docs.prod-cloud-ocb.orange-business.com/api/iam/en-us_topic_0057845583.html
# (Mandatory) FE_Token="xxxx"

# (Optionnal) ID of Project in Flexible Engine
#FE_Project_ID="xxxx"

# (Optionnal) ID of DNS Zone in Flexible Engine
#FE_Zone_ID="xxxx"

# (Mandatory) URL to Endpoint API DNS Flexible Engine
FE_Api="https://dns.prod-cloud-ocb.orange-business.com/v2"


########  Public functions below  #####################
# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add TXT record
dns_flexibleengine_add() {
  _debug "DNS Challenge : dns_flexibleengine_add()"
  fulldomain=$1
  txtvalue=$2

  FE_Token="${FE_Token:-$(_readaccountconf_mutable FE_Token)}"
  FE_Project_ID="${FE_Project_ID:-$(_readaccountconf_mutable FE_Project_ID)}"
  FE_Zone_ID="${FE_Zone_ID:-$(_readaccountconf_mutable FE_Zone_ID)}"

  if [ "$FE_Token" ]; then
    _saveaccountconf_mutable FE_Token "$FE_Token"
    _saveaccountconf_mutable FE_Project_ID "$FE__ID"
    _saveaccountconf_mutable FE_Zone_ID "$FE_Zone_ID"
  else
    _err "You didn't specify a User Token API yet."
    _err "You can get yours from https://docs.prod-cloud-ocb.orange-business.com/en-us/api/iam/en-us_topic_0057845583.html"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain "
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting TXT records"
  # GET /v2/zones/{zone_id}/recordsets?limit={limit}&offset={offset}&marker={marker}&tags={tags}&status={status}&type={type}&name={name}&id={id}&sort_key={sort_key}&sort_dir={sort_dir}
  #   HELP : https://docs.prod-cloud-ocb.orange-business.com/api/dns/dns_api_64004.html
  _flexibleengine_rest GET "zones/${_domain_id}/recordsets?type=TXT&name=$fulldomain"

  # If not contains 'total_count":' == Request API Error
  if ! echo "$response" | tr -d " " | grep \"total_count\": >/dev/null; then
    _err "Error"
    return 1
  fi
  # For wildcard cert, the main root domain and the wildcard domain have the same txt subdomain name, so
  # we cannot use updating anymore.

  _info "Adding TXT record"
  # POST /v2/zones/{zone_id}/recordsets
  #  HELP : https://docs.prod-cloud-ocb.orange-business.com/api/dns/dns_api_64001.html
  #  HINT : The TTL parameter must be in ranges from 300 to 2147483647.
  #  Sample Record
  #  {
  #    "type": "TXT",
  #    "name": "_acme-challenge.sub2.sub1.domain.ltd",
  #    "ttl": 300,
  #    "records": [
  #      "\"CHALLENGE-TEST\""
  #    ]
  #  }

  if _flexibleengine_rest POST "zones/$_domain_id/recordsets" "{\"type\":\"TXT\",\"name\":\"$fulldomain\",\"ttl\":300,\"records\":[\"\\\"$txtvalue\\\"\"]}"; then
    if _contains "$response" "$txtvalue"; then
      _info "Added, OK"
      return 0
    elif _contains "$response" "conflicts with Record Set"; then
      _info "TXT Record already exists for this domain, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1

}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_flexibleengine_rm() {
  _debug "DNS Challenge : dns_flexibleengine_rm()"
  fulldomain=$1
  txtvalue=$2

  FE_Token="${FE_Token:-$(_readaccountconf_mutable FE_Token)}"
  FE_Project_ID="${FE_Project_ID:-$(_readaccountconf_mutable FE_Project_ID)}"
  FE_Zone_ID="${FE_Zone_ID:-$(_readaccountconf_mutable FE_Zone_ID)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting TXT records"
  # GET GET /v2/recordsets?zone_type={zone_type}&limit={limit}&marker={marker}&offset={offset}&tags={tags}&status={status}&type={type}&name={name}&id={id}&records={records}&sort_key={sort_key}&sort_dir={sort_dir}
  #   HELP : https://docs.prod-cloud-ocb.orange-business.com/api/dns/dns_api_64003.html
  _flexibleengine_rest GET "zones/${_domain_id}/recordsets?type=TXT&name=$fulldomain&records=$txtvalue"
  # Return "metadata":{"total_count":N} (Where N is the number of TXT records)

  # If not contains 'total_count":' == Request API Error
  if ! echo "$response" | tr -d " " | _egrep_o "\"total_count\":" ; then
    _err "Error: $response"
    return 1
  fi

  # Find number (N) of records == {"total_count":N}
  count=$(echo "$response" | _egrep_o "\"total_count\":*[^},]*" | cut -d : -f 2 | tr -d " ")
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Don't need to remove."
  else
    # Find Record ID
    record_id=$(echo "$response" | _egrep_o "\"id\": *\"[^\"]*\"" | cut -d : -f 2 | tr -d \" | _head_n 1 | tr -d " ")
    _debug "record_id" "$record_id"
    if [ -z "$record_id" ]; then
      _err "Can not get record id to remove."
      return 1
    fi
    # DELETE /v2/zones/{zone_id}/recordsets/{recordset_id}
    #   HELP : https://docs.prod-cloud-ocb.orange-business.com/en-us/api/dns/dns_api_64005.html
    if ! _flexibleengine_rest DELETE "zones/$_domain_id/recordsets/$record_id"; then
      _err "Delete record error."
      return 1
    fi
    _info "DNS TXT Records deleted."
    # We find this part '"status":"PENDING_DELETE"' in message
    #   If this status if found, we return Code 0 (Ok)
    echo "$response" | tr -d " " | _egrep_o "\"status\":\"PENDING_DELETE\""
  fi

}

####################  Private functions below  #################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  _debug "DNS Challenge : _get_root()"
  domain=$1
  i=1
  p=1
  # Use Zone ID directly if provided
  if [ "$FE_Zone_ID" ]; then
    _info "DNS zone ID is SET"
    if ! _flexibleengine_rest GET "zones/$FE_Zone_ID"; then
      return 1
    else
      # If contains 'total_count":1' == Request API Success !
      if _contains "$response" '"total_count":1'; then
        _domain=$(echo "$response" | _egrep_o "\"name\": *\"[^\"]*\"" | cut -d : -f 2 | tr -d \" | _head_n 1 | tr -d " ")
        if [ "$_domain" ]; then
          _cutlength=$((${#domain} - ${#_domain} - 1))
          _sub_domain=$(printf "%s" "$domain" | cut -c "1-$_cutlength")
          _domain_id=$FE_Zone_ID
          return 0
        else
          return 1
        fi
      else
        return 1
      fi
    fi
  fi

  # Trying to find Root Domain
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    # This part 'Project ID' is not fully tested :-/
    if [ "$FE_Project_ID" ]; then
      _debug "Enterprise Project ID => SET"
      if ! _flexibleengine_rest GET "zones?name=$h&enterprise_project_id=$FE_Project_ID"; then
        return 1
      fi
    else
      _debug "Enterprise Project ID => NOT SET"
      if ! _flexibleengine_rest GET "zones?name=$h"; then
        return 1
      fi
    fi
    # If contains 'total_count":1' == Request API Success !
    if _contains "$response" "\"name\":\"$h\"" || _contains "$response" '"total_count":1'; then
      _domain_id=$(echo "$response" | _egrep_o "\[.\"id\": *\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \" | tr -d " ")
      _debug _domain_id "$_domain_id"
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_flexibleengine_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  token_trimmed=$(echo "$FE_Token" | tr -d '"')

  export _H1="Content-Type: application/json"
  if [ "$token_trimmed" ]; then
    # Write Authentication header
    # Note : Flexible Engine Use "X-Auth-Token" as header for Authentication
    export _H2="X-Auth-Token: $token_trimmed"
  fi

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$FE_Api/$ep" "" "$m")"
  else
    response="$(_get "$FE_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
