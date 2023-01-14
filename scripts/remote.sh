source ${script_path}/lib/tfcloud.sh

function deploy_remote {
    echo "@calling deploy_remote"


    case "${tf_action}" in
        migrate)
            migrate_to_remote
            ;;
        *)
            terraform_init_remote
            ;;
    esac
}

function terraform_init_remote {
    echo "@calling terraform_init_remote"

    echo "Terraform base code: ${landingzone_name}"
    cd ${landingzone_name}

    tfstate_configure remote
    tf_command=$(purge_command remote ${tf_command})

    get_logged_user_object_id

    export TF_VAR_tf_name=${TF_VAR_tf_name:="$(basename $(pwd)).tfstate"}
    export TF_VAR_tf_plan=${TF_VAR_tf_plan:="$(basename $(pwd)).tfplan"}
    export STDERR_FILE="${TF_DATA_DIR}/${TF_VAR_environment}/tfstates/${TF_VAR_level}/${TF_VAR_workspace}/$(basename $(pwd))_stderr.txt"

    mkdir -p "${TF_DATA_DIR}/${TF_VAR_environment}/tfstates/${TF_VAR_level}/${TF_VAR_workspace}"

    if [ ! -f ${landingzone_name}/backend.hcl ]; then
        error ${LINENO} "Could not find ${landingzone_name}/backend.hcl"
    fi

    case "${tf_action}" in
        "migrate")
            migrate_command=$(purge_command migrate ${tf_command} $1)
            create_workspace ${gitops_tfcloud_workspace_mode}
            cat ${landingzone_name}/backend.hcl
            echo "migrate command ${migrate_command}"
            terraform -chdir=${landingzone_name} \
                init ${migrate_command} \
                -upgrade \
                -migrate-state \
                -backend-config=${landingzone_name}/backend.hcl | grep -P '^- (?=Downloading|Using|Finding|Installing)|^[^-]'
            ;;
        *)
            echo "gitops_agent_pool_execution_mode set to ${gitops_agent_pool_execution_mode}"
            case "${gitops_agent_pool_execution_mode}" in
                local)
                    rm -f -- "${TF_DATA_DIR}/${TF_VAR_environment}/terraform.tfstate"
                    create_workspace ${gitops_tfcloud_workspace_mode}
                    terraform -chdir=${landingzone_name} \
                        init \
                        -upgrade \
                        -reconfigure  \
                        -backend-config=${landingzone_name}/backend.hcl | grep -P '^- (?=Downloading|Using|Finding|Installing)|^[^-]'
                    
                    get_logged_user_object_id
                    case "${tf_action}" in
                        "plan")
                            echo "calling plan"
                            plan_remote
                            ;;
                        "apply")
                            echo "calling apply"
                            apply_remote
                            ;;
                        "validate")
                            echo "calling validate"
                            validate
                            ;;
                        "destroy")
                            destroy_remote
                            ;;
                        *)
                            other
                            ;;
                    esac

                    ;;
                agent)
                    ${script_path}/terraform-enterprise-push.sh
                    ;;
                *)
                    error ${LINENO} "-gitops-agent-pool-execution-mode only local or agent supported. Got ${gitops_agent_pool_execution_mode}"
                    ;;
            esac
            ;;
    esac

    RETURN_CODE=$? && echo "Line ${LINENO} - Terraform init return code ${RETURN_CODE}"


}

function plan_remote {
    echo "@calling plan_remote"

    echo "running terraform plan remote (execution mode: ${gitops_agent_pool_execution_mode}) with ${tf_command} ${1}"
    echo " -TF_VAR_workspace: ${TF_VAR_workspace}"
    mkdir -p "${TF_DATA_DIR}/${TF_VAR_environment}/tfstates/${TF_VAR_level}/${TF_VAR_workspace}"
    rm -f $STDERR_FILE

    information "running plan..."
    command="terraform -chdir=${landingzone_name} \
        plan ${tf_command} ${1} \
        -refresh=true \
        -lock=false \
      $(if [ "${gitops_agent_pool_execution_mode}" = "local" ]; then
        echo " -state=\"${TF_DATA_DIR}/${TF_VAR_environment}/tfstates/${TF_VAR_level}/${TF_VAR_workspace}/${TF_VAR_tf_name}\" "
        echo "-out=\"${TF_DATA_DIR}/${TF_VAR_environment}/tfstates/${TF_VAR_level}/${TF_VAR_workspace}/${TF_VAR_tf_plan}\" 2>$STDERR_FILE | tee ${tf_output_file}"
      else
        echo " -state=\"${TF_DATA_DIR}/${TF_VAR_environment}/tfstates/${TF_VAR_level}/${TF_VAR_workspace}/${TF_VAR_tf_name}\" 2>$STDERR_FILE | tee ${tf_output_file}"
      fi)"

    eval $command

    RETURN_CODE=$? && echo "Terraform plan return code: ${RETURN_CODE}"

    if [ -s $STDERR_FILE ]; then
        if [ ${tf_output_file+x} ]; then cat $STDERR_FILE >> ${tf_output_file}; fi
        echo "Terraform returned errors:"
        cat $STDERR_FILE
        RETURN_CODE=2000
    fi

    if [ $RETURN_CODE != 0 ]; then
        error ${LINENO} "Error running terraform plan" $RETURN_CODE
    fi

    if [ ! -z ${tf_plan_file} ]; then
        echo "Copying plan file to ${tf_plan_file}"
        cp "${TF_DATA_DIR}/${TF_VAR_environment}/tfstates/${TF_VAR_level}/${TF_VAR_workspace}/${TF_VAR_tf_plan}" "${tf_plan_file}"
    fi
}

function apply_remote {
    echo "@calling apply_remote"

    echo 'running terraform apply'
    rm -f $STDERR_FILE

    if [ -z ${tf_plan_file} ] && [ "${gitops_agent_pool_execution_mode}" != "local" ]; then
        echo "Plan not provided with -p or --plan so calling terraform plan"
        plan_remote

        local tf_plan_file="${TF_DATA_DIR}/${TF_VAR_environment}/tfstates/${TF_VAR_level}/${TF_VAR_workspace}/${TF_VAR_tf_plan}"
    fi

    command="terraform -chdir=${landingzone_name} \
        apply \
        -state=\"${TF_DATA_DIR}/${TF_VAR_environment}/tfstates/${TF_VAR_level}/${TF_VAR_workspace}/${TF_VAR_tf_name}\" \
      $(if [ "${gitops_agent_pool_execution_mode}" = "local" ]; then
        echo "| tee ${tf_output_file}"
      else
        echo "${tf_plan_file} | tee ${tf_output_file}"
      fi)"

    eval $command

    RETURN_CODE=$? && echo "Terraform apply return code: ${RETURN_CODE}"

    if [ -s $STDERR_FILE ]; then
        if [ ${tf_output_file+x} ]; then cat $STDERR_FILE >> ${tf_output_file}; fi
        echo "Terraform returned errors:"
        cat $STDERR_FILE
        RETURN_CODE=2001
    fi

    if [ $RETURN_CODE != 0 ]; then
        error ${LINENO} "Error running terraform apply" $RETURN_CODE
    fi

}

function destroy_remote {
    echo "@calling destroy_remote"

    echo 'running terraform destroy remote'
    rm -f $STDERR_FILE

    if [ -z ${tf_plan_file} ]; then
        echo "Plan not provided with -p or --plan so calling terraform plan"
        plan_remote "-destroy"

        local tf_plan_file="${TF_DATA_DIR}/${TF_VAR_environment}/tfstates/${TF_VAR_level}/${TF_VAR_workspace}/${TF_VAR_tf_plan}"
    fi

    terraform -chdir=${landingzone_name} \
      apply \
      -refresh=false \
      $(parse_command_destroy_with_plan ${tf_command}) ${tf_approve} \
      "${tf_plan_file}"

    RETURN_CODE=$? && echo "Terraform apply return code: ${RETURN_CODE}"

    if [ -s $STDERR_FILE ]; then
        if [ ${tf_output_file+x} ]; then cat $STDERR_FILE >> ${tf_output_file}; fi
        echo "Terraform returned errors:"
        cat $STDERR_FILE
        RETURN_CODE=2001
    fi

    if [ $RETURN_CODE != 0 ]; then
        error ${LINENO} "Error running terraform apply" $RETURN_CODE
    fi

}

function migrate {
    case "${gitops_terraform_backend_type}" in
        remote)
            migrate_to_remote
            ;;
        *)
            error ${LINENO} "Only migration from azurerm to Terraform Cloud or Enterprise is supported." 1
    esac

}

function migrate_to_remote {
    information "@calling migrate_to_remote"

    get_storage_id
    login_as_launchpad
    get_logged_user_object_id

    tfstate_configure 'azurerm'
    terraform_init_azurerm

    tfstate_configure 'remote'
    terraform_init_remote

    information "Checking lease on blob file:"
    information " - tfstate name: ${TF_VAR_tf_name}"
    information " - storage account: ${TF_VAR_tfstate_storage_account_name}"
    information " - container: ${azurerm_workspace}"
    az storage blob lease acquire \
        -b ${TF_VAR_tf_name} \
        -c ${azurerm_workspace} \
        --account-name ${TF_VAR_tfstate_storage_account_name} \
        --auth-mode login

    success "A lock has been set on the source tfstate to prevent future migration:"
    information " - tfstate name: ${TF_VAR_tf_name}"
    information " - storage account: ${TF_VAR_tfstate_storage_account_name}"
    information " - container: ${azurerm_workspace}"

    success "Migration complete to remote ${TF_VAR_tf_cloud_hostname}/${TF_VAR_tf_cloud_organization}/${TF_VAR_workspace}"
}
