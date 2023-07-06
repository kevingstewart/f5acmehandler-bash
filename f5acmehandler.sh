#!/usr/bin/env bash

## F5 BIG-IP ACME Client (Dehydrated) Handler Utility
## Author: kevin-at-f5-dot-com
## Description: 
## Configuration and installation: 


## ================================================== ##
## DEFINE COMMON VARIABLES ========================== ##
## ================================================== ##
THRESHOLD=30			         ## Threshold in days when a certificate must be renewed
ALWAYS_GENERATE_KEY=false     ## Set to true to always generate a private key. Otherwise a CSR is created from an existing key
ERRORLOG=true                 ## Set to true to generate error logging (to stdout)
DEBUGLOG=true                 ## Set to true to generate debug logging (to stdout)
REPORT=true                   ## Set to true to generate a report



## ================================================== ##
## FUNCTIONS ======================================== ##
## ================================================== ##

ACMEDIR=/shared/acme

## Function: process_errors --> 
process_errors () {
   local ERR="${1}"
   if [[ "$ERR" =~ ^"ERROR" && "$ERRORLOG" == "true" ]]; then echo -e ">> ${ERR}"; fi
   if [[ "$ERR" =~ ^"DEBUG" && "$DEBUGLOG" == "true" ]]; then echo -e ">> ${ERR}"; fi
}

## Function: process_report --> 
# process_report () {
   
# }

## Function: (handler) generate_new_cert_key
## This function triggers the ACME client directly, which then calls the configured hook script to assist 
## in auto-generating a new certificate and private key. The hook script then installs the cert/key if not
## present, or updates the existing cert/key via TMSH transaction.
generate_new_cert_key() {
   local DOMAIN="${1}" COMMAND="${2}"
   process_errors "DEBUG (handler function: generate_new_cert_key)\n   DOMAIN=${DOMAIN}\n   COMMAND=${COMMAND}\n"

   cmd="${ACMEDIR}/dehydrated -c -g -d ${DOMAIN} $(echo ${COMMAND} | tr -d '"')"
   do=$(eval $cmd 2>&1 | cat)
   process_errors "DEBUG (handler: ACME client output):\n$do\n"
}

## Function: (handler) generate_cert_from_csr
## This function triggers a CSR creation via TMSH, collects and passes the CSR to the ACME client, then collects
## the renewed certificate and replaces the existing certificate via TMSH transaction.
generate_cert_from_csr() {
   local DOMAIN="${1}" COMMAND="${2}"
   process_errors "DEBUG (handler function: generate_cert_from_csr)\n   DOMAIN=${DOMAIN}\n   COMMAND=${COMMAND}\n"

   ## Commencing acme renewal process - first delete and recreate a csr for domain
   tmsh delete sys crypto csr ${DOMAIN} > /dev/null 2>&1
   tmsh create sys crypto csr ${DOMAIN} common-name ${DOMAIN} subject-alternative-name DNS:${DOMAIN} key ${DOMAIN}

   ## Dump csr to cert.csr in DOMAIN subfolder
   mkdir -p ${ACMEDIR}/certs/${DOMAIN} 2>&1
   tmsh list sys crypto csr ${DOMAIN} |sed -n '/-----BEGIN CERTIFICATE REQUEST-----/,/-----END CERTIFICATE REQUEST-----/p' > ${ACMEDIR}/certs/${DOMAIN}/cert.csr
   process_errors "DEBUG (handler: csr):\n$(cat ${ACMEDIR}/certs/${DOMAIN}/cert.csr)\n"

   ## Issue acme client call and dump renewed cert to certs/{domain}/cert.pem
   cmd="${ACMEDIR}/dehydrated -s ${ACMEDIR}/certs/${DOMAIN}/cert.csr $(echo ${COMMAND} | tr -d '"')"
   do=$(eval $cmd 2>&1 | cat)
   process_errors "DEBUG (handler: ACME client output):\n$do\n"

   if [[ $do =~ "# CERT #" ]]
   then
      cat $do 2>&1 | sed -n '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p;/-END CERTIFICATE-/q' > ${ACMEDIR}/certs/${DOMAIN}/cert.pem
   else
      process_errors "ERROR: ACME client failure: $do\n"
      return
   fi

   ## Create transaction to update existing cert and key
   (echo create cli transaction
      echo install sys crypto cert ${DOMAIN} from-local-file ${ACMEDIR}/certs/${DOMAIN}/cert.pem
      echo submit cli transaction
   ) | tmsh > /dev/null 2>&1
   process_errors "DEBUG (handler: tmsh transaction) Installed certificate via tmsh transaction\n"

   ## Clean up objects
   tmsh delete sys crypto csr ${DOMAIN}
   rm -rf ${ACMEDIR}/certs/${DOMAIN}
   process_errors "DEBUG (handler: cleanup) Cleaned up CSR and ${DOMAIN} folder\n\n"
}


## Function: process_handler_config --> take dg config string as input and perform cert renewal processes
process_handler_config () {
   ## Split input line into {DOMAIN} and {COMMAND} variables.
   IFS="=" read -r DOMAIN COMMAND <<< $1
   process_errors "DEBUG ==================================================\n>> DEBUG (handler function: process_handler_config)\n>> DEBUG ==================================================\n   VAR: DOMAIN=${DOMAIN}\n   VAR: COMMAND=${COMMAND}\n"
   
   ## Error test: check if cert exists in BIG-IP config
   certexists=true && [[ "$(tmsh list sys crypto cert ${DOMAIN} 2>&1)" == "" ]] && certexists=false

   ## If cert exists or ALWAYS_GENERATE_KEYS is true, call the generate_new_cert_key function
   if [[ "$certexists" == "false" || "$ALWAYS_GENERATE_KEY" == "true" ]]
   then
      process_errors "DEBUG: Certificate does not exist, or ALWAYS_GENERATE_KEY is true --> call generate_new_cert_key.\n"
      generate_new_cert_key "$DOMAIN" "$COMMAND"

   else
      ## Else call the generate_cert_from_csr function
      process_errors "DEBUG: Certificate exists, or ALWAYS_GENERATE_KEY is false --> call generate_cert_from_csr.\n"

      ## Collect today's date and certificate expiration date
      date_cert=$(tmsh list sys crypto cert ${DOMAIN} | grep expiration | awk '{$1=$1}1' | sed 's/expiration //')
      date_cert=$(date -d "$date_cert" "+%Y%m%d")
      date_today=$(date +"%Y%m%d")
      date_test=$(date --date=@$(($date_cert - $date_today)) +'%d')
      process_errors "DEBUG (handler: dates)\n   date_cert=$date_cert\n   date_today=$date_today\n   date_test=$date_test\n"

      ## If certificate is past the threshold window, initiate renewal
      if [ $THRESHOLD -le $date_test ]
      then
         process_errors "DEBUG (handler: threshold) THRESHOLD ($THRESHOLD) -le date_test ($date_test) - Starting renewal process for ${DOMAIN}\n"
         generate_cert_from_csr "$DOMAIN" "$COMMAND"
      else
         process_errors "DEBUG (handler: bypass) Bypassing renewal process for ${DOMAIN} - Certificate within threshold\n"
         return
      fi
   fi
}



## == MAIN ===============================================================
process_errors "DEBUG (handler) Initiating ACME client handler function\n"

## Test for and only run on active BIG-IP
ACTIVE=$(tmsh show cm failover-status | grep ACTIVE | wc -l)
if [[ "${ACTIVE}" = "1" ]]; then
   ## Read from the config data group and loop through keys:values
   config=true && [[ "$(tmsh list ltm data-group internal acme_config_dg 2>&1)" =~ "was not found" ]] && config=false

   if ($config)
   then
      IFS=";" && for v in $(tmsh list ltm data-group internal acme_config_dg one-line | sed -e 's/ltm data-group internal acme_config_dg { records { //;s/ \} type string \}//;s/ { data /=/g;s/ \} /;/g;s/ \}//'); do process_handler_config $v; done
   else
      process_errors "ERROR: There was an error accessing the acme_config_dg data group. Please re-install\n"
      exit 1
   fi
fi







