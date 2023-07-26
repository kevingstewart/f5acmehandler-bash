#!/usr/bin/env bash

## F5 BIG-IP ACME Client (Dehydrated) Hook Script
## Maintainer: kevin-at-f5-dot-com
## Description: 
## Configuration and installation: 


## ================================================== ##
## DEFINE COMMON VARIABLES ========================== ##
## ================================================== ##
ZEROCYCLE=3                      ## Set to preferred number of zeroization cycles for shredding created private keys
CREATEPROFILE=false              ## Set to true to generate new client SSL profiles with new certs/keys
DEBUGLOG=true                    ## Set to true to generate debug logging (to stdout)



## ================================================== ##
## FUNCTIONS ======================================== ##
## ================================================== ##

## Static processing variables - do not touch
ACMEDIR=/shared/acme


process_errors () {
   local ERR="${1}"
   if [[ "$ERR" =~ ^"DEBUG" && "$DEBUGLOG" == "true" ]]; then echo -e "\n>> ${ERR}"; fi
}

startup_hook() {
    process_errors "DEBUG (hook function: startup_hook)\n"
}

deploy_challenge() {
    ## Add a record to the data group
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
    process_errors "DEBUG (hook function: deploy_challenge)\n   DOMAIN=${DOMAIN}\n   TOKEN_FILENAME=${TOKEN_FILENAME}\n   TOKEN_VALUE=${TOKEN_VALUE}\n"
    tmsh modify ltm data-group internal acme_handler_dg records add { \"${TOKEN_FILENAME}\" { data \"${TOKEN_VALUE}\" } }
}

clean_challenge() {
    ## Delete the record from the data group
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
    process_errors "DEBUG (hook function: clean_challenge)\n   DOMAIN=${DOMAIN}\n   TOKEN_FILENAME=${TOKEN_FILENAME}\n   TOKEN_VALUE=${TOKEN_VALUE}\n"
    tmsh modify ltm data-group internal acme_handler_dg records delete { \"${TOKEN_FILENAME}\" }
}

sync_cert() {
    local KEYFILE="${1}" CERTFILE="${2}" FULLCHAINFILE="${3}" CHAINFILE="${4}" REQUESTFILE="${5}"
    process_errors "DEBUG (hook function: sync_cert)\n   KEYFILE=${KEYFILE}\n   CERTFILE=${CERTFILE}\n   FULLCHAINFILE=${FULLCHAINFILE}\n   CHAINFILE=${CHAINFILE}\n   REQUESTFILE=${REQUESTFILE}\n"
}

deploy_cert() {
    ## Import new cert and key
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}" TIMESTAMP="${6}"
    process_errors "DEBUG (hook function: deploy_cert)\n   DOMAIN=${DOMAIN}\n   KEYFILE=${KEYFILE}\n   CERTFILE=${CERTFILE}\n   FULLCHAINFILE=${FULLCHAINFILE}\n   CHAINFILE=${CHAINFILE}\n   TIMESTAMP=${TIMESTAMP}\n"

    ## Test if cert and key exist
    key=true && [[ "$(tmsh list sys file ssl-key ${DOMAIN} 2>&1)" =~ "was not found" ]] && key=false
    cert=true && [[ "$(tmsh list sys file ssl-cert ${DOMAIN} 2>&1)" =~ "was not found" ]] && cert=false

    if ($key && $cert)
    then
        ## Create transaction to update existing cert and key
        process_errors "DEBUG (hook function: deploy_cert -> Updating existing cert and key)\n"
        (echo create cli transaction
         echo install sys crypto key ${DOMAIN} from-local-file ${ACMEDIR}/certs/${DOMAIN}/privkey.pem
         echo install sys crypto cert ${DOMAIN} from-local-file ${ACMEDIR}/certs/${DOMAIN}/cert.pem
         echo submit cli transaction
        ) | tmsh

    else
        ## Create cert and key
        process_errors "DEBUG (hook function: deploy_cert -> Installing new cert and key)\n"
        tmsh install sys crypto key ${DOMAIN} from-local-file ${ACMEDIR}/certs/${DOMAIN}/privkey.pem
        tmsh install sys crypto cert ${DOMAIN} from-local-file ${ACMEDIR}/certs/${DOMAIN}/cert.pem
    fi

    ## Clean up and zeroize local storage (via shred)
    cd ${ACMEDIR}/certs/${DOMAIN}
    find . -type f -print0 | xargs -0 shred -fuz -n ${ZEROCYCLE}
    cd ${ACMEDIR}/
    rm -rf ${ACMEDIR}/certs/${DOMAIN}/


    ## Test if corresponding clientssl profile exists
    if ($CREATEPROFILE)
    then
        clientssl=true && [[ "$(tmsh list ltm profile client-ssl "${DOMAIN}_clientssl" 2>&1)" =~ "was not found" ]] && clientssl=false

        if [[ $clientssl == "false" ]]
        then
            ## Create the clientssl profile
            tmsh create ltm profile client-ssl "${DOMAIN}_clientssl" cert-key-chain replace-all-with { ${DOMAIN} { key ${DOMAIN} cert ${DOMAIN} } } 
        fi
    fi
}

deploy_ocsp() {
    local DOMAIN="${1}" OCSPFILE="${2}" TIMESTAMP="${3}"
    process_errors "DEBUG (hook function: deploy_ocsp)\n   DOMAIN=${DOMAIN}\n   OCSPFILE=${OCSPFILE}\n   TIMESTAMP=${TIMESTAMP}\n"
}

unchanged_cert() {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"
    process_errors "DEBUG (hook function: unchanged_cert)\n   DOMAIN=${DOMAIN}\n   KEYFILE=${KEYFILE}\n   CERTFILE=${CERTFILE}\n   FULLCHAINFILE=${FULLCHAINFILE}\n   CHAINFILE=${CHAINFILE}\n"
}

invalid_challenge() {
    local DOMAIN="${1}" RESPONSE="${2}"
    process_errors "DEBUG (hook function: invalid_challenge)\n   DOMAIN=${DOMAIN}\n   RESPONSE=${RESPONSE}\n"
}

request_failure() {
    local STATUSCODE="${1}" REASON="${2}" REQTYPE="${3}" HEADERS="${4}"
    process_errors "DEBUG (hook function: request_failure)\n   STATUSCODE=${STATUSCODE}\n   REASON=${REASON}\n   REQTYPE=${REQTYPE}\n   HEADERS=${HEADERS}\n"
}

generate_csr() {
    local DOMAIN="${1}" CERTDIR="${2}" ALTNAMES="${3}"
    process_errors "DEBUG (hook function: generate_csr)\n   DOMAIN={DOMAIN}\n   CERTDIR=${CERTDIR}\n   ALTNAMES=${ALTNAMES}\n"
}

exit_hook() {
    local ERROR="${1:-}"
    process_errors "DEBUG (hook function: exit_hook)\n   ERROR=${ERROR}\n"
}

HANDLER="$1"; shift
if [[ "${HANDLER}" =~ ^(deploy_challenge|clean_challenge|sync_cert|deploy_cert|deploy_ocsp|unchanged_cert|invalid_challenge|request_failure|generate_csr|startup_hook|exit_hook)$ ]]; then
    "$HANDLER" "$@"
fi
