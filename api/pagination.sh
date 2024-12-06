if [[ -z "${ROX_API_TOKEN}" ]]; then
  echo >&2 "ROX_API_TOKEN must be set"
  exit 1
fi


api_url="https://central-stackrox.apps.ocp.ralvares.com/v1/deployments"
limit_per_page=100
total_alerts=325
offset=0

export total_alerts=$(curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://central-stackrox.apps.ocp.ralvares.com/v1/deploymentscount | jq -r '.count')


while [ $offset -lt $total_alerts ]; do
    # Calculate the remaining alerts
    remaining_alerts=$((total_alerts - offset))

    # Set the limit for the current request
    if [ $remaining_alerts -lt $limit_per_page ]; then
        current_limit=$remaining_alerts
    else
        current_limit=$limit_per_page
    fi

    # Make the API request using curl
    curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    "$api_url?query=&pagination.offset=$offset&pagination.limit=$current_limit" | jq -r

    # Update the offset for the next iteration
    offset=$((offset + current_limit))
done
