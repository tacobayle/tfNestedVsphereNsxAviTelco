#!/bin/bash
#
if [ -f "../../nsx.json" ]; then
  jsonFile="../../nsx.json"
else
  echo "ERROR: no json file found"
  exit 1
fi
nsx_ip=$(jq -r .vcenter.dvs.portgroup.management.nsx_ip $jsonFile)
cookies_file="bash/create_bgp_cookies.txt"
headers_file="bash/create_bgp_headers.txt"
rm -f $cookies_file $headers_file
#
nsx_api () {
  # $1 is the amount of retry
  # $2 is the time to pause between each retry
  # $3 type of HTTP method (GET, POST, PUT, PATCH)
  # $4 cookie file
  # $5 http header
  # $6 http data
  # $7 NSX IP
  # $8 API endpoint
  retry=$1
  pause=$2
  attempt=0
  echo "HTTP $3 API call to https://$7/$8"
  while true ; do
    response=$(curl -k -s -X $3 --write-out "\n%{http_code}" -b $4 -H "`grep -i X-XSRF-TOKEN $5 | tr -d '\r\n'`" -H "Content-Type: application/json" -d "$6" https://$7/$8)
    response_body=$(sed '$ d' <<< "$response")
    response_code=$(tail -n1 <<< "$response")
    if [[ $response_code == 2[0-9][0-9] ]] ; then
      echo "  HTTP $3 API call to https://$7/$8 was successful"
      break
    else
      echo "  Retrying HTTP $3 API call to https://$7/$8, http response code: $response_code, attempt: $attempt"
    fi
    if [ $attempt -eq $retry ]; then
      echo "  FAILED HTTP $3 API call to https://$7/$8, response code was: $response_code"
      echo "$response_body"
      exit 255
    fi
    sleep $pause
    ((attempt++))
  done
}
#
/bin/bash bash/create_nsx_api_session.sh admin $TF_VAR_nsx_password $nsx_ip $cookies_file $headers_file
IFS=$'\n'
#
#
# BGP config
#
for tier0 in $(jq -c -r .nsx.config.tier0s[] $jsonFile)
do
  if [[ $(echo $tier0 | jq 'has("bgp")') == "true" ]] ; then
    echo "Enabling BGP on tier0 called: $(echo $tier0 | jq -r -c .display_name) with local AS: $(echo $tier0 | jq -r -c .bgp.local_as_num)"
    nsx_api 6 10 "PATCH" $cookies_file $headers_file '{"enabled": "true", "local_as_num": "'$(echo $tier0 | jq -r -c .bgp.local_as_num)'", "ecmp": "'$(echo $tier0 | jq -r -c .bgp.ecmp)'"}' "$nsx_ip/policy/api/v1/infra/tier-0s/$(echo $tier0 | jq -r -c .display_name)/locale-services/default/bgp"
    echo "retrieving tier0 called: $(echo $tier0 | jq -r -c .display_name) interfaces details"
    nsx_api 6 10 "GET" $cookies_file $headers_file '' "$nsx_ip/policy/api/v1/infra/tier-0s/$(echo $tier0 | jq -r -c .display_name)/locale-services/default/interfaces"
    tier0_interfaces=$(echo $response_body)
    tier0_interfaces_ips="[]"
    for interface in $(echo $tier0_interfaces | jq -c -r .results[])
    do
      tier0_interfaces_ips=$(echo $tier0_interfaces_ips | jq -c -r '. += ['$(echo $interface | jq -c '.subnets[0].ip_addresses[0]')']')
    done
    nsx_api 6 10 "GET" $cookies_file $headers_file '' "$nsx_ip/policy/api/v1/infra/tier-0s/$(echo $tier0 | jq -r -c .display_name)/locale-services/default/interfaces"
    neighbor_count=1
    for neighbor in $(echo $tier0 | jq -c -r .bgp.neighbors[])
    do
      echo "Adding neighbor called: peer$neighbor_count to the tier0 called $(echo $tier0 | jq -r -c .display_name) with remote AS number: $(echo $neighbor | jq -r -c .remote_as_num), with remote neighbor IP: $(echo $neighbor | jq -r -c .neighbor_address), with source IP: $(echo $tier0_interfaces_ips | jq -c -r .))"
      nsx_api 1 1 "PUT" $cookies_file $headers_file '{"neighbor_address": "'$(echo $neighbor | jq -r -c .neighbor_address)'", "remote_as_num": "'$(echo $neighbor | jq -r -c .remote_as_num)'", "source_addresses": '$(echo $tier0_interfaces_ips | jq -c -r .)'}' "$nsx_ip/policy/api/v1/infra/tier-0s/$(echo $tier0 | jq -r -c .display_name)/locale-services/default/bgp/neighbors/peer$neighbor_count"
      ((neighbor_count++))
    done
  fi
done
