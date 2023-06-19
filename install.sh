## Simple Dehydrated Acme (F5 BIG-IP) - Install Utility
## Author: kevin.g.stewart@gmail.com
##
## Dehydrated source: https://github.com/dehydrated-io/dehydrated
## 
## Purpose: Wrapper for Dehydrated Acme client to simplify usage on F5 BIG-IP
##
## Usage:
## - Execute: curl -s https://raw.githubusercontent.com/kevingstewart/simple-dehydrated-acme-f5/main/install.sh | bash
##

## Create working directory
mkdir -p /shared/acme/wellknown > /dev/null 2>&1

## Download and place files
curl -s https://raw.githubusercontent.com/dehydrated-io/dehydrated/master/dehydrated -o /shared/acme/dehydrated && chmod +x /shared/acme/dehydrated
curl -s https://raw.githubusercontent.com/kevingstewart/simple-dehydrated-acme-f5/main/config -o /shared/acme/config
curl -s https://raw.githubusercontent.com/kevingstewart/simple-dehydrated-acme-f5/main/domains.txt -o /shared/acme/domains.txt
curl -s https://raw.githubusercontent.com/kevingstewart/simple-dehydrated-acme-f5/main/hook_script_f5.sh -o /shared/acme/hook_script_f5.sh && chmod +x /shared/acme/hook_script_f5.sh

## Create BIG-IP data group
tmsh create ltm data-group internal acme_handler_dg type string > /dev/null 2>&1

## Create BIG-IP iRule
tmsh create ltm rule acme_handler_rule when HTTP_REQUEST priority 2 {if { [string tolower [HTTP::uri]] starts_with \"/.well-known/acme-challenge/\" } {set response_content [class lookup [substr [HTTP::uri] 28] acme_handler_dg]\;if { \$response_content ne \"\" } { HTTP::respond 200 -version auto content \$response_content noserver Content-Type {text/plain} Content-Length [string length \$response_content] Cache-Control no-store } else { HTTP::respond 503 -version auto content \"\<html\>\<body\>\<h1\>503 - Error\<\/h1\>\<p\>Content not found.\<\/p\>\<\/body\>\<\/html\>\" noserver Content-Type {text/html} Cache-Control no-store }\;unset response_content\;event disable all\;return}}  > /dev/null 2>&1

## Create scheduling





