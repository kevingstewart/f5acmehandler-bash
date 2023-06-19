## Simple Dehydrated Acme (F5 BIG-IP) - Install Utility
## Author: kevin.g.stewart@gmail.com
##
## Dehydrated source: https://github.com/dehydrated-io/dehydrated
## 
## Purpose: Wrapper for Dehydrated Acme client to simplify usage on F5 BIG-IP
##
## Usage:
## - Execute: curl https://raw.githubusercontent.com/kevingstewart/simple-dehydrated-acme/install-f5.sh | bash
##

## Create working directory
mkdir -p /shared/acme/wellknown

## Download and place files
curl https://raw.githubusercontent.com/dehydrated-io/dehydrated/master/dehydrated -o /shared/acme/dehydrated && chmod +x /shared/acme/dehydrated
curl https://raw.githubusercontent.com/kevingstewart/simple-dehydrated-acme/config -o /shared/acme/config
curl https://raw.githubusercontent.com/kevingstewart/simple-dehydrated-acme/domains.txt -o /shared/acme/domains.txt
curl https://raw.githubusercontent.com/kevingstewart/simple-dehydrated-acme/hook_script.sh -o /shared/acme/hook_script_f5.sh && chmod +x /shared/acme/hook_script_f5.sh

## Create BIG-IP data group
tmsh create ltm data-group internal acme_handler_dg type string

## Create BIG-IP iRule
tmsh create ltm rule acme_handler_rule when HTTP_REQUEST priority 2 {if { [string tolower [HTTP::uri]] starts_with \"/.well-known/acme-challenge/\" } {set response_content [class lookup [substr [HTTP::uri] 28] acme_handler_dg]\;if { \$response_content ne \"\" } { HTTP::respond 200 -version auto content \$response_content noserver Content-Type {text/plain} Content-Length [string length \$response_content] Cache-Control no-store } else { HTTP::respond 503 -version auto content \"\<html\>\<body\>\<h1\>503 - Error\<\/h1\>\<p\>Content not found.\<\/p\>\<\/body\>\<\/html\>\" noserver Content-Type {text/html} Cache-Control no-store }\;unset response_content\;event disable all\;return}}

## Create scheduling





