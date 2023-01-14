check_terraform_session() {
  debug "tfcloud"

  if [ -e "${REMOTE_credential_path_json}" ]; then
    if [ -z ${TF_VAR_tf_cloud_hostname} ]; then
      token=$(cat ${REMOTE_credential_path_json})
      export TF_VAR_tf_cloud_hostname=$(echo ${token} | jq -r '.credentials | keys_unsorted[] as $k | {$k} | .k ')
    fi
  else
    error ${LINENO} "You need to login Terraform Cloud or Enterprise using 'terraform login'"
  fi

  if [ -z ${TF_VAR_tf_cloud_organization} ]; then
    error ${LINENO} " When you connect to Terraform Cloud or Enterprise you must set the organization name with the attribute (-TF_VAR_tf_cloud_organization"
  fi
  success "Connected to Terraform: ${TF_VAR_tf_cloud_hostname}/${TF_VAR_tf_cloud_organization}"
}

get_remote_token() {
    debug "@calling get_remote_token"

    if [ -z "${REMOTE_credential_path_json}" -o -z "${TF_VAR_tf_cloud_hostname}" ]
    then
        error ${LINENO} "You must provide REMOTE_credential_path_json and TF_VAR_tf_cloud_hostname'." 1
    fi

    information "Getting token from ${REMOTE_credential_path_json} for ${TF_VAR_tf_cloud_hostname}"

    export REMOTE_ORG_TOKEN=${REMOTE_ORG_TOKEN:=$(cat ${REMOTE_credential_path_json} | jq -r .credentials.\"${TF_VAR_tf_cloud_hostname}\".token)}

    if [ -z "${REMOTE_ORG_TOKEN}" ]; then
        error ${LINENO} "You must provide either a REMOTE_ORG_TOKEN token or run 'terraform login'." 1
    fi
}

create_workspace() {
  echo "@calling create_workspace for ${TF_VAR_workspace}"

  get_remote_token
  agent_pool=$(generate_agent_pool_name ${gitops_agent_pool_name})
  URL=https://${TF_VAR_tf_cloud_hostname}/api/v2/organizations/${TF_VAR_tf_cloud_organization}/workspaces

  workspace=$(curl -s \
    --header "Authorization: Bearer $REMOTE_ORG_TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    --request GET \
    ${URL}?search%5Bname%5D=${TF_VAR_workspace} | jq -r .data)

  jq_command=$(cat <<-EOF
  jq -n \
      '
{
  "data": {
    "attributes": {
      "name": "${TF_VAR_workspace}",
      $(if [ "${gitops_execution_mode}" = "agent" ]; then 
          if [ check_terraform_cloud_agent_exist ${agent_pool} ]; then
            echo "\"agent-pool-id\": \"${TF_CLOUD_AGENT_POOL_ID}\","
          fi
      fi)
      "execution-mode": "${gitops_execution_mode}"
    },
    "type": "workspaces"
  }
}
      ' 
EOF
)
  eval ${jq_command}
  BODY=$(eval ${jq_command})

  if [ "${workspace}" == "[]" ]; then
    METHOD="POST"
  else
    workspace_id=$(echo ${workspace} | jq -r .[0].id)
    METHOD="PATCH"
    URL="${URL}/${workspace_id}"
  fi

  echo ${BODY}
  echo ${URL}

  echo "Trigger api call."

  curl -s \
    --header "Authorization: Bearer $REMOTE_ORG_TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    --request ${METHOD} \
    --data "${BODY}" \
    $URL

  echo ""
  if [ "${gitops_execution_mode}" == "remote" ]; then
    information "Agent pool: ${agent_pool} for workspace ${TF_VAR_workspace} set to execution mode: ${gitops_execution_mode}"
  else
    information "workspace ${TF_VAR_workspace} set to execution mode: ${gitops_execution_mode}"
  fi
}

check_terraform_cloud_agent_exist() {
    debug "@calling check_terraform_cloud_agent_exist for ${1}"

# ${1} agent pool name
#
# return false (1) if the agent-pool does not exist
# return true (0) if the agent-pool exist. Also export the agent_pool_id

  debug ${TF_VAR_tf_cloud_hostname}
  debug ${TF_VAR_tf_cloud_organization}
  debug ${1}

  result=$(curl -s \
    --header "Authorization: Bearer ${REMOTE_ORG_TOKEN}" \
    --header "Content-Type: application/vnd.api+json" \
    --request GET \
    "https://${TF_VAR_tf_cloud_hostname}/api/v2/organizations/${TF_VAR_tf_cloud_organization}/agent-pools" | jq -r ".data[] | select (.attributes.name==\"${1}\")")

  if [ "${result}" = "" ]; then
    # false
    return 1
  else
    export TF_CLOUD_AGENT_POOL_ID=$(echo ${result} | jq -r .id)
    return 0
  fi
  
}

generate_agent_pool_name() {

  if [ -z ${TF_VAR_level} ]; then
    agent_pool="${1}"
  else
    agent_pool="${TF_VAR_level}_${1}"
  fi

  echo ${agent_pool}
}

process_terraform_cloud_agent_pool() {
    
    agent_pool=$(generate_agent_pool_name ${1})

    information "@calling process_terraform_cloud_agent_pool for ${agent_pool}"

# ${1} agent pool name

    get_remote_token

    if ! check_terraform_cloud_agent_exist ${agent_pool}; then

      BODY=$( jq -n \
        --arg type "agent-pools" \
        --arg name "${agent_pool}" \
        '
{
  "data": {
    "type": $type,
    "attributes": 
    {
      "name": $name
    } 
  }
}
        ' ) && debug " - body: $BODY"
        

      information "Trigger agent-pool creation."
      
      response=$(curl -s \
          --header "Authorization: Bearer $REMOTE_ORG_TOKEN" \
          --header "Content-Type: application/vnd.api+json" \
          --request POST \
          --data "${BODY}" \
          https://${TF_VAR_tf_cloud_hostname}/api/v2/organizations/${TF_VAR_tf_cloud_organization}/agent-pools | jq -r)

      debug "Response: ${response}"

      debug ${response} | jq -r .data.id

      export TF_CLOUD_AGENT_POOL_ID=$(echo ${response} | jq -r .data.id) && success "Agent pool \"${agent_pool}\" created: ${TF_CLOUD_AGENT_POOL_ID}"

    else
      success "Agent pool \"${1}_${TF_VAR_level}\" is already created."
    fi

    create_agent_token ${TF_CLOUD_AGENT_POOL_ID} ${agent_pool} "Cloud Adoption Framework - Rover"
}

create_agent_token() {
  debug "@call create_agent_token"

# ${1} agent pool id
# ${2} agent pool name
# ${3} description

  JSON=$( jq -n \
  --arg type "authentication-tokens" \
  --arg description "${3}" \
  '
{
  "data": {
    "type": $type,
    "attributes": 
    {
      "description": $description
    } 
  }
}
  ' ) && debug " - body: $JSON"

  export tfc_agent_pool_token=$(curl -s \
    --header "Authorization: Bearer $REMOTE_ORG_TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    --request POST \
    --data "${JSON}" \
    https://${TF_VAR_tf_cloud_hostname}/api/v2/agent-pools/${1}/authentication-tokens | jq -r .data.attributes.token)
  
    register_gitops_secret ${gitops_pipelines} "${TF_VAR_level}_TF_CLOUD_AGENT_POOL_AUTH_TOKEN" ${tfc_agent_pool_token}

}
