## Simple Dehydrated Acme (F5 BIG-IP) - Install Utility
## Author: kevin.g.stewart@gmail.com
##
## Dehydrated source: https://github.com/dehydrated-io/dehydrated
## 
## Purpose: Wrapper for Dehydrated Acme client to simplify usage on F5 BIG-IP
##
## Usage:
## - Execute: curl -s https://<repo-url>/install.sh | bash
##

acmeclient_url="https://raw.githubusercontent.com/dehydrated-io/dehydrated/master"
f5acmehandler_url="https://raw.githubusercontent.com/kevingstewart/simple-dehydrated-acme/main"

## Download and place files
mkdir -p /shared/acme
curl -s ${acmeclient_url}/dehydrated -o /shared/acme/dehydrated && chmod +x /shared/acme/dehydrated
curl -s ${f5acmehandler_url}/f5acmehandler.sh -o /shared/acme/f5acmehandler.sh && chmod +x /shared/acme/f5acmehandler.sh
curl -s ${f5acmehandler_url}/f5hook.sh -o /shared/acme/f5hook.sh && chmod +x /shared/acme/f5hook.sh
curl -s ${f5acmehandler_url}/config -o /shared/acme/config

## Create BIG-IP data groups (acme_handler_dg, acme_config_dg)
tmsh create ltm data-group internal acme_handler_dg type string > /dev/null 2>&1
tmsh create ltm data-group internal acme_config_dg type string > /dev/null 2>&1

## Create BIG-IP iRule (acme_handler_rule)
tmsh create ltm rule acme_handler_rule when HTTP_REQUEST priority 2 {if { [string tolower [HTTP::uri]] starts_with \"/.well-known/acme-challenge/\" } {set response_content [class lookup [substr [HTTP::uri] 28] acme_handler_dg]\;if { \$response_content ne \"\" } { HTTP::respond 200 -version auto content \$response_content noserver Content-Type {text/plain} Content-Length [string length \$response_content] Cache-Control no-store } else { HTTP::respond 503 -version auto content \"\<html\>\<body\>\<h1\>503 - Error\<\/h1\>\<p\>Content not found.\<\/p\>\<\/body\>\<\/html\>\" noserver Content-Type {text/html} Cache-Control no-store }\;unset response_content\;event disable all\;return}}  > /dev/null 2>&1

## Create the log file
touch /var/log/acmehandler

## Create scheduling





