#!/usr/bin/env bash

## F5 BIG-IP ACME Client (Dehydrated) Handler Utility
## Author: kevin-at-f5-dot-com
## Description: 
## Configuration and installation: 


## ================================================== ##
## DEFINE COMMON VARIABLES ========================== ##
## ================================================== ##
THRESHOLD=40		               ## Threshold in days when a certificate must be renewed
ALWAYS_GENERATE_KEY=false        ## Set to true to always generate a private key. Otherwise a CSR is created from an existing key

ERRORLOG=true                    ## Set to true to generate error logging (to stdout)
DEBUGLOG=true                    ## Set to true to generate debug logging (to stdout)
LOGFILE=/var/log/acmehandler     ## Set to location of the error/debug log



## ================================================== ##
## FUNCTIONS ======================================== ##
## ================================================== ##

## Static variables - do not touch
ACMEDIR=/shared/acme
STANDARD_OPTIONS="-x -k ${ACMEDIR}/f5hook.sh -t http-01"
REGISTER_OPTIONS="--register --accept-terms"
FORCERENEW="no"
SINGLEDOMAIN=""

## Function: process_errors --> 
process_errors () {
   local ERR="${1}"
   timestamp=$(date +%F_%T)
   if [[ "$ERR" =~ ^"ERROR" && "$ERRORLOG" == "true" ]]; then echo -e ">> [${timestamp}]  ${ERR}" >> ${LOGFILE}; fi
   if [[ "$ERR" =~ ^"DEBUG" && "$DEBUGLOG" == "true" ]]; then echo -e ">> [${timestamp}]  ${ERR}" >> ${LOGFILE}; fi
}

## Function: (handler) generate_new_cert_key
## This function triggers the ACME client directly, which then calls the configured hook script to assist 
## in auto-generating a new certificate and private key. The hook script then installs the cert/key if not
## present, or updates the existing cert/key via TMSH transaction.
generate_new_cert_key() {
   local DOMAIN="${1}" COMMAND="${2}"
   process_errors "DEBUG (handler function: generate_new_cert_key)\n   DOMAIN=${DOMAIN}\n   COMMAND=${COMMAND}\n"

   cmd="${ACMEDIR}/dehydrated ${STANDARD_OPTIONS} -c -g -d ${DOMAIN} $(echo ${COMMAND} | tr -d '"')"
   process_errors "DEBUG (handler: ACME client command):\n$cmd\n"
   do=$(eval $cmd 2>&1 | cat | sed 's/^/   /')
   process_errors "DEBUG (handler: ACME client output):\n$do\n"
}

## Function: (handler) generate_cert_from_csr
## This function triggers a CSR creation via TMSH, collects and passes the CSR to the ACME client, then collects
## the renewed certificate and replaces the existing certificate via TMSH transaction.
generate_cert_from_csr() {
   local DOMAIN="${1}" COMMAND="${2}"
   process_errors "DEBUG (handler function: generate_cert_from_csr)\n   DOMAIN=${DOMAIN}\n   COMMAND=${COMMAND}\n"

   ## Fetch existing subject-alternative-name (SAN) values from the certificate
   certsan=$(tmsh list sys crypto cert ${DOMAIN} | grep subject-alternative-name | awk '{$1=$1}1' | sed 's/subject-alternative-name //')
   ## If certsan is empty, assign the domain/CN value
   if [ -z "$certsan" ]
   then
      certsan="DNS:${DOMAIN}"
   fi

   ## Commencing acme renewal process - first delete and recreate a csr for domain
   tmsh delete sys crypto csr ${DOMAIN} > /dev/null 2>&1
   tmsh create sys crypto csr ${DOMAIN} common-name ${DOMAIN} subject-alternative-name "${certsan}" key ${DOMAIN}
   
   ## Dump csr to cert.csr in DOMAIN subfolder
   mkdir -p ${ACMEDIR}/certs/${DOMAIN} 2>&1
   tmsh list sys crypto csr ${DOMAIN} |sed -n '/-----BEGIN CERTIFICATE REQUEST-----/,/-----END CERTIFICATE REQUEST-----/p' > ${ACMEDIR}/certs/${DOMAIN}/cert.csr
   process_errors "DEBUG (handler: csr):\n$(cat ${ACMEDIR}/certs/${DOMAIN}/cert.csr | sed 's/^/   /')\n"

   ## Issue acme client call and dump renewed cert to certs/{domain}/cert.pem
   cmd="${ACMEDIR}/dehydrated ${STANDARD_OPTIONS} -s ${ACMEDIR}/certs/${DOMAIN}/cert.csr $(echo ${COMMAND} | tr -d '"')"
   process_errors "DEBUG (handler: ACME client command):\n   $cmd\n"
   do=$(eval $cmd 2>&1 | cat | sed 's/^/   /')
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

   if [[ ( ! -z "$SINGLEDOMAIN" ) && ( ! "$SINGLEDOMAIN" == "$DOMAIN" ) ]]
   then
      ## Break out of function if SINGLEDOMAIN is specified and this pass is not for the matching domain
      continue
   else
      process_errors "DEBUG (handler function: process_handler_config)\n   --domain argument specified for ($DOMAIN)\n"
   fi

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
      if [[ ! "${FORCERENEW}" == "yes" ]]
      then
         date_cert=$(tmsh list sys crypto cert ${DOMAIN} | grep expiration | awk '{$1=$1}1' | sed 's/expiration //')
         date_cert=$(date -d "$date_cert" "+%Y%m%d")
         date_today=$(date +"%Y%m%d")
         date_test=$(date --date=@$(($date_cert - $date_today)) +'%d')
         process_errors "DEBUG (handler: dates)\n   date_cert=$date_cert\n   date_today=$date_today\n   date_test=$date_test\n"
      else
         date_test=10000
         process_errors "DEBUG (handler: dates)\n   --force argument specified, forcing renewal\n"
      fi

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


## Function: process_handler_init --> utility function to:
## -- Check for configuration data group errors
## -- Check cert/profile/VIP structure
##    - Test if client SSL profile exists for certificate --> fail/report if false
##    - Test if HTTPS VIP does not exist for SSL profile --> fail/report if true (missing)
##    - Test if HTTP VIP does not exist (that matches HTTPS IP) --> create and add iRule if true (missing), add iRule if false (present)
## -- Register new domains (if not already registered)
process_handler_init() {
   init_report="Init Report:\n"
   
   ## Create list of existing client SSL profiles and attached certificates (profile=cert)
   certlist=$(tmsh -q list ltm profile client-ssl recursive one-line | sed -E 's/ltm profile client-ssl ([^[:space:]]+)\s.+\scert\s([^[:space:]]+)\s.*/\1=\2/g')
   
   ## Read from the config data group and loop through entries
   config=true && [[ "$(tmsh list ltm data-group internal acme_config_dg 2>&1)" =~ "was not found" ]] && config=false
   if ($config)
   then
      ## Loop through data group config (domain=value)
      IFS=";" && for v in $(tmsh list ltm data-group internal acme_config_dg one-line | sed -e 's/ltm data-group internal acme_config_dg { records { //;s/ \} type string \}//;s/ { data /=/g;s/ \} /;/g;s/ \}//')
      do
         ## Extract domain and command values
         IFS="=" read -r DOMAIN COMMAND <<< $v
         init_report="${init_report}  -- ${DOMAIN}:\n"


         #####################
         ## INIT process: Check for configuration data group errors
         #####################
         ## Regex validate domain entry
         dom_regex='^([a-zA-Z0-9](([a-zA-Z0-9-]){0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
         if [[ ! "$DOMAIN" =~ $dom_regex ]]
         then
            init_report="${init_report}\tERROR: Configuration entry ($DOMAIN) is incorrect\n"
            continue 
         fi

         ## Config entry must include "--ca" option
         if [[ ! "$COMMAND" =~ "--ca " ]]
         then
            init_report="${init_report}\tERROR: Configuration entry for ($DOMAIN) must include a \"--ca\" option\n"
            continue 
         fi


         #####################
         ## INIT process: Check cert/profile/VIP structure
         ## - Test if client SSL profile exists for certificate --> fail/report if false
         ## - Test if HTTPS VIP does not exist for SSL profile --> fail/report if true (missing)
         ## - Test if HTTP VIP does not exist (that matches HTTPS IP) --> create and add iRule if true (missing), add iRule if false (present)
         #####################
         ## Test if client SSL profile exists for certificate (DOMAIN certificate is attached to any client SSL profile) --> fail/report if false
         if echo $certlist | grep -q "=${DOMAIN}"
         then
            ## True: matching client SSL profile
            clientssl_profile=$(echo $certlist | grep $DOMAIN | awk -F"=" '{print $1}')
            
            ## Test if HTTPS VIP does not exist for SSL profile --> fail/report if true (missing)
            if ! tmsh -q list ltm virtual recursive one-line | grep -q $clientssl_profile
            then
               ## True: matching client SSL profile but no assigned VIP
               found_profile=$(echo $certlist | grep $DOMAIN | awk -F"=" '{print $1}')
               # init_report="${init_report}  -- (${DOMAIN}):\tA client SSL profile exists (${found_profile}), but is not attached to any virtual server\n"
               init_report="${init_report}\tERROR: A client SSL profile exists (${found_profile}), but is not attached to any virtual server\n"
               continue
            else
               ## False: matching client SSL profile AND assigned VIP
               found_vip=$(tmsh -q list ltm virtual recursive one-line | grep www.f5labs.com_clientssl | sed -E 's/ltm virtual ([^[:space:]]+)\s.*/\1/g')
               found_vip_ip=$(tmsh -q list ltm virtual ${found_vip} destination | tr -d '\n' |sed -E 's/.*destination\s([^[:space:]]+):.*/\1/g')
               
               ## Test if HTTP VIP does not exist (that matches HTTPS IP) --> create and add iRule if true (missing), add iRule if false (present)
               if ! tmsh -q list ltm virtual recursive one-line | grep -q "${found_vip_ip}:http "
               then
                  ## True: matching :http VIP
                  # init_report="${init_report}  -- (${DOMAIN}):\tA client SSL profile and HTTPS VIP exist, but no port 80 VIP exists. Creating...\n"
                  init_report="${init_report}\tA client SSL profile and HTTPS VIP exist, but no port 80 VIP exists. Creating...\n"
                  
                  ## Get :https VIP VLANs
                  found_vip_vlans=$(tmsh -q list ltm virtual ${found_vip} vlans | tr -d '\n' | sed -E 's/.*vlans\s+\{\s+([^}]+)\}\}/\1/g;s/\s+/ /g')

                  ## Create the iRule. Assume it does not exist
                  tmsh create ltm rule acme_handler_rule when HTTP_REQUEST priority 2 {if { [string tolower [HTTP::uri]] starts_with \"/.well-known/acme-challenge/\" } {set response_content [class lookup [substr [HTTP::uri] 28] acme_handler_dg]\;if { \$response_content ne \"\" } { HTTP::respond 200 -version auto content \$response_content noserver Content-Type {text/plain} Content-Length [string length \$response_content] Cache-Control no-store } else { HTTP::respond 503 -version auto content \"\<html\>\<body\>\<h1\>503 - Error\<\/h1\>\<p\>Content not found.\<\/p\>\<\/body\>\<\/html\>\" noserver Content-Type {text/html} Cache-Control no-store }\;unset response_content\;event disable all\;return}}  > /dev/null 2>&1

                  ## Create the HTTP VIP, attach the iRule
                  cmd="tmsh create ltm virtual \"_acme_handler_${DOMAIN}\" destination ${found_vip_ip}:80 vlans replace-all-with { ${found_vip_vlans} } profiles replace-all-with { http } rules { acme_handler_rule }"
                  eval $cmd > /dev/null 2>&1
               else
                  ## False: :http VIP exists, add iRule. Assume it is not added
                  # init_report="${init_report}  -- (${DOMAIN}):\tA client SSL profile and HTTPS VIP exist, and port 80 VIP exists. Adding iRule to HTTP VIP...\n"
                  init_report="${init_report}\tA client SSL profile and HTTPS VIP exist, and port 80 VIP exists. Adding iRule to HTTP VIP...\n"
                  
                  ## Get HTTP VIP name
                  found_vip_http=$(tmsh -q list ltm virtual recursive one-line | grep "${found_vip_ip}:http " | sed -E 's/ltm virtual ([^[:space:]]+)\s.*/\1/g')
                  
                  ## Get HTTP VIP existing iRules
                  found_vip_http_rules=$(tmsh -q list ltm virtual ${found_vip_http} rules | tr -d '\n' | sed -E 's/.*rules\s+\{\s+([^}]+)\}\}/\1/g;s/\s+/ /g')
                  
                  ## Create the iRule. Assume it does not exist
                  tmsh create ltm rule acme_handler_rule when HTTP_REQUEST priority 2 {if { [string tolower [HTTP::uri]] starts_with \"/.well-known/acme-challenge/\" } {set response_content [class lookup [substr [HTTP::uri] 28] acme_handler_dg]\;if { \$response_content ne \"\" } { HTTP::respond 200 -version auto content \$response_content noserver Content-Type {text/plain} Content-Length [string length \$response_content] Cache-Control no-store } else { HTTP::respond 503 -version auto content \"\<html\>\<body\>\<h1\>503 - Error\<\/h1\>\<p\>Content not found.\<\/p\>\<\/body\>\<\/html\>\" noserver Content-Type {text/html} Cache-Control no-store }\;unset response_content\;event disable all\;return}}  > /dev/null 2>&1

                  ## Add iRule to VIP
                  cmd="tmsh modify ltm virtual ${found_vip_http} rules { ${found_vip_http_rules} acme_handler_rule }"
                  eval $cmd > /dev/null 2>&1
               fi
            fi
         else
            ## False: no matching client SSL profile - fail/report
            # init_report="${init_report}  -- (${DOMAIN}):\tNo client SSL profile exists. No additional actions performed.\n"
            init_report="${init_report}\tERROR: No client SSL profile exists. No additional actions performed.\n"
            continue
         fi

         
         #####################
         ## INIT process: Register new domains (if not already registered)
         #####################

         ## Extract --ca and --config values
         if [[ "$COMMAND" =~ "--ca " ]]; then COMMAND_CA=$(echo "$COMMAND" | sed -E 's/.*(--ca+\s[^[:space:]]+).*/\1/g;s/"//g'); else COMMAND_CA=""; fi
         if [[ "$COMMAND" =~ "--config " ]]; then COMMAND_CONFIG=$(echo "$COMMAND" | sed -E 's/.*(--config+\s[^[:space:]]+).*/\1/g;s/"//g'); else COMMAND_CONFIG=""; fi

         ## Get base URL from COMMAND_CA
         BASEURL=$(echo $COMMAND_CA | sed -E 's/.*(https:\/\/[^\/]+).*/\1/g')

         ## Loop through accounts folder and find existing registrations
         if [[ $(find ${ACMEDIR}/accounts/ -type d | wc -l) -le 1 ]]
         then
            ## No existing registrations (accounts folder empty) --> perform registration
            init_report="${init_report}\tNo existing registered for specified CA. ($COMMAND_CA). Performing registration...\n"
            cmd="${ACMEDIR}/dehydrated --register --accept-terms ${COMMAND_CA} ${COMMAND_CONFIG}"
            do=$(eval $cmd 2>&1 | cat | sed 's/^/        /')
            init_report="${init_report}$do\n"
         else
            ## Exiting registrations (accounts for not empty) --> loop through folder and look for a match (existing registration)
            for acct in $(ls ${ACMEDIR}/accounts)
            do
               TESTURL=$(base64 -d <<< $acct 2>&1)
               if [[ "$TESTURL" =~ "$BASEURL" ]]
               then
                  ## Matching registration found --> stop
                  init_report="${init_report}\tAlready registered for specified CA ($COMMAND_CA).\n"
               else
                  ## No matching registration found --> perform registration
                  init_report="${init_report}\tNo existing registered for specified CA ($COMMAND_CA). Performing registration...\n"
                  cmd="${ACMEDIR}/dehydrated --register --accept-terms ${COMMAND_CA} ${COMMAND_CONFIG}"
                  do=$(eval $cmd 2>&1 | cat | sed 's/^/        /')
                  init_report="${init_report}$do\n"
               fi
            done
         fi
      done

      ## Print report to stdout
      printf "${init_report}\n\n"
   else
      process_errors "ERROR: There was an error accessing the acme_config_dg data group. Please re-install\n"
      exit 1
   fi
}


## Function: process_handler_main --> loop through config data group and pass DOMAIN and COMMAND values to client handlers
process_handler_main() {
   process_errors "DEBUG (handler) Initiating ACME client handler function\n"

   ## Test for and only run on active BIG-IP
   ACTIVE=$(tmsh show cm failover-status | grep ACTIVE | wc -l)
   if [[ "${ACTIVE}" = "1" ]]
   then
      ## Create wellknown folder
      mkdir /tmp/wellknown > /dev/null 2>&1
      
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
}


## Function: command_help --> display help information in stdout
## Usage: --help
command_help() {
  printf "\nUsage: %s [--help]\n"
  printf "Usage: %s [--init]\n"
  printf "Usage: %s [--force] [--domain <domain>]\n\n"
  printf "Default (no arguments): renewal operations\n"
  printf -- "\nParameters:\n"
  printf " --help:\t\tPrint this help information\n"
  printf " --init:\t\tDetect configuration errors, register new domains, create port 80 VIPs\n"
  printf " --force:\t\tForce renewal (override data checks)\n"
  printf " --domain <domain>:\tRenew a single domain (ex. --domain www.f5labs.com)\n\n\n"
}


## Function: main --> process command line arguments
main() {
   while (( ${#} )); do
      case "${1}" in
         --help)
           command_help >&2
           exit 0
           ;;

         --init)
           process_handler_init
           exit 0
           ;;

         --force)
           FORCERENEW="yes"
           ;;

         --domain)
           shift 1
           if [[ -z "${1:-}" ]]; then
             printf "\nThe specified command requires additional parameters. See help:" >&2
             echo >&2
             command_help >&2
             exit 1
           fi
           SINGLEDOMAIN="${1}"
           ;;

         *)
           process_errors "DEBUG (handler function: main)\n   Launching default renew operations\n"
           ;;
      esac
   shift 1
   done

   ## Call main function
   process_handler_main
}


## Script entry
main "${@:-}"







