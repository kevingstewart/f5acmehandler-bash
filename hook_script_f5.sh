#!/usr/bin/env bash

startup_hook() {
    echo "PROCESS: startup_hook"
}

deploy_challenge() {
    ## Add a record to the data group
    echo "PROCESS: deploy_challenge"
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
    tmsh modify ltm data-group internal acme_handler_dg records add { \"${TOKEN_FILENAME}\" { data \"${TOKEN_VALUE}\" } }
}

clean_challenge() {
    ## Delete the record from the data group
    echo "PROCESS: clean_challenge"
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
    tmsh modify ltm data-group internal acme_handler_dg records delete { \"${TOKEN_FILENAME}\" }
}

sync_cert() {
    echo "PROCESS: sync_cert"
    local KEYFILE="${1}" CERTFILE="${2}" FULLCHAINFILE="${3}" CHAINFILE="${4}" REQUESTFILE="${5}"
}

deploy_cert() {
    ## Import new cert and key
    echo "PROCESS: deploy_cert"
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}" TIMESTAMP="${6}"

    ## Test if cert and key exist
    key=true && [[ "$(tmsh list sys file ssl-key ${DOMAIN} 2>&1)" =~ "was not found" ]] && key=false
    cert=true && [[ "$(tmsh list sys file ssl-cert ${DOMAIN} 2>&1)" =~ "was not found" ]] && cert=false

    if ($key && $cert)
    then
        ## Create transaction to update existing cert and key
        echo "PROCESS: deploy_cert :: updating existing cert and key"
        (echo create cli transaction
         echo install sys crypto key ${DOMAIN} from-local-file ./certs/${DOMAIN}/privkey.pem
         echo install sys crypto cert ${DOMAIN} from-local-file ./certs/${DOMAIN}/cert.pem
         echo submit cli transaction
        ) | tmsh

    else
        ## Create cert and key
        tmsh install sys crypto key ${DOMAIN} from-local-file ./certs/${DOMAIN}/privkey.pem
        tmsh install sys crypto cert ${DOMAIN} from-local-file ./certs/${DOMAIN}/cert.pem
    fi

    ## Test if corresponding clientssl profile exists
    clientssl=true && [[ "$(tmsh list ltm profile client-ssl "${DOMAIN}_clientssl" 2>&1)" =~ "was not found" ]] && clientssl=false

    if [[ $clientssl == "false" ]]
    then
        ## Create the clientssl profile
        tmsh create ltm profile client-ssl "${DOMAIN}_clientssl" cert-key-chain replace-all-with { ${DOMAIN} { key ${DOMAIN} cert ${DOMAIN} } } 
    fi
}

deploy_ocsp() {
    echo "PROCESS: deploy_ocsp"
    local DOMAIN="${1}" OCSPFILE="${2}" TIMESTAMP="${3}"
}

unchanged_cert() {
    echo "PROCESS: unchanged_cert"
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"
}

invalid_challenge() {
    echo "PROCESS: invalid_challenge"
    local DOMAIN="${1}" RESPONSE="${2}"
}

request_failure() {
    echo "PROCESS: request_failure"
    local STATUSCODE="${1}" REASON="${2}" REQTYPE="${3}" HEADERS="${4}"
}

generate_csr() {
    echo "PROCESS: generate_csr"
    local DOMAIN="${1}" CERTDIR="${2}" ALTNAMES="${3}"
}

exit_hook() {
    echo "PROCESS: exit_hook"
    local ERROR="${1:-}"
}


HANDLER="$1"; shift
if [[ "${HANDLER}" =~ ^(deploy_challenge|clean_challenge|sync_cert|deploy_cert|deploy_ocsp|unchanged_cert|invalid_challenge|request_failure|generate_csr|startup_hook|exit_hook)$ ]]; then
    "$HANDLER" "$@"
fi
