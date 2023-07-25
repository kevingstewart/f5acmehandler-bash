# Acme Certificate Renewal Utility for F5 BIG-IP

### An Acme client wrapper function for integration and advanced features on the F5 BIG-IP

This utility defines a wrapper for the Bash-based [Dehydrated](https://github.com/dehydrated-io/dehydrated) ACMEv2 client, supporting direct integration with F5 BIG-IP, and including advanced features:

* Simple installation, configuration, and scheduling
* Supports renewal with existing private keys to enable certificate automation in HSM/FIPS environments
* Supports per-domain configurations, and multiple Acme services
* Supports External Account Binding (EAB)
* Supports OCSP and periodic revocation testing
* Supports explicit proxy egress
* Supports SAN certificate renewal
* Supports debug logging

<br />

------------
### ${\textbf{\color{blue}Installation\ and\ Configuration}}$
Installation to the BIG-IP is simple. The only constraint is that the certificate objects installed on the BIG-IP **must** be named after the certificate subject name. For example, if the certificate subject name is ```www.f5labs.com```, then the installed certificate and key must also be named ```www.f5labs.com```. Certificate automation is predicated on this naming construct. 

* **Step 1**: SSH to the BIG-IP shell and run the following command to install the required components:

    ```
    curl -s https://raw.githubusercontent.com/kevingstewart/f5acmehandler-bash/main/install.sh | bash
    ```

* **Step 2**: Update the new ```acme_config_dg``` data group and add entries for each managed domain (certificate subject). See the **Global Configuration Options** section
   below for additional details.

    ```
    www.foo.com := --ca https://acme-v02.api.letsencrypt.org/directory
    www.bar.com := --ca https://acme.zerossl.com/v2/DV90 --config /shared/acme/config_www_example_com
    www.baz.com := --ca https://acme.locallab.com:9000/directory -a rsa
    ```

* **Step 3**: Adjust the client configuration ```config``` file as needed for your environment. This utility allows for per-domain configurations, for example, when EAB is needed for some providers, but not others. See the **Acme Dehydrated Client Configuration Options** section below for additional details.

* **Step 4**: Run the following command in ```/shared/acme``` whenever the data group is updated. This command will check the validity of the configuration data group, and
   register any providers not already registered. See the **Utility Function Command Line Options** section below for additional details.

    ```
    ./f5acmehandler --init
    ```

* **Step 5**: Initiate an Acme fetch. This command will loop through the data group and perform required Acme certificate renewal operations for each configured domain. By default, if no certificate and key         exists, Acme renewal will generate a new certificate and key. If a private key exists, a CSR is generated from that existing key to renew the certificate only. This it to support HSM/FIPS environments, but can    be disabled. See the **Miscellaneous Configuration Options** section below for additional details.

    ```
    ./f5acmehandler
    ```

* **Step 6**: Define scheduling. See the **Scheduling** section below for additional details.

<br />

------------
### ${\textbf{\color{blue}Configuration\ Details}}$

<details>
<summary><b>Global Configuration Options</b></summary>

Global configuration options are specified in the ```acme_config_dg``` data group for each domain (certificate subject). Each entry in the data group must include a **String**: the domain name (ex. www.f5labs.com), and a **Value** consisting of a number of configuration options:

<br />

| **Value Options** | **Description**                                 | **Examples**                                                                       | **Required**|
|-------------------|-------------------------------------------------|------------------------------------------------------------------------------------|-------------|
| --ca              | Defines the Acme provider URL                   | --ca https://acme-v02.api.letsencrypt.org/directory           (Let's Encrypt)<br />--ca https://acme-staging-v02.api.letsencrypt.org/directory   (LE Staging)<br />--ca https://acme.zerossl.com/v2/DV90                         (ZeroSSL)<br />--ca https://api.buypass.com/acme/directory                   (Buypass)<br />--ca https://api.test4.buypass.no/acme/directory              (Buypass Test)       |     Yes     |
| --config          | Defines an alternate config file<br />(default /shared/acme/config)                | --config /shared/acme/config_www_f5labs_com                                        |     No      |
| -a                | Overrides the required leaf certificate<br />algorithm specified in the config file.<br />Options:<br />- rsa<br />- prime256v1<br />- secp384r1         | -a rsa<br />-a prime256v1<br />-a secp384r1                                                                             |     No      |   

<br />

Examples:

```
www.foo.com := --ca https://acme-v02.api.letsencrypt.org/directory
www.bar.com := --ca https://acme.zerossl.com/v2/DV90 --config /shared/acme/config_www_example_com
www.baz.com := --ca https://acme.locallab.com:9000/directory -a rsa

```

</details>

<details>
<summary><b>Acme Dehydrated Client Configuration Options</b></summary>

Within the ```/shared/acme/config``` file are a number of additional client attributes. This utility allows for per-domain configurations, for example, when EAB is needed for some providers, but not others.

| **Config Options**    | **Description**                                                                             |
|-----------------------|---------------------------------------------------------------------------------------------|
| CURL_OPTS             | Defines specific attributes used in the underlying Curl functions. This could minimally<br />include:<br />--http1.1          = use HTTP/1.1<br />-k                 = ignore certificate errors<br />-x \<proxy-url\>     = use an explicit proxy     |
| KEY_ALGO              | Defines the required leaf certificate algorithm (rsa, prime256v1, or secp384r1)             |
| KEYSIZE               | Defines the required leaf certificate key size (default: 4096)                              |
| CONTACT_EMAIL         | Defines the registration account name and must be unique per provider requirements          |
| OCSP_MUST_STAPLE      | Option to add CSR-flag indicating OCSP stapling to be mandatory (default: no)               |
| RENEW_DAYS            | Minimum days before expiration to automatically renew certificate (default: 30)             |
| OCSP_FETCH            | Fetch OCSP responses (default: no)                                                          |
| OCSP_DAYS             | OCSP refresh interval (default: 5 days)                                                     |
| EAB_KID/EAB_HMAC_KEY  | Extended Account Binding (EAB) support                                                      |


</details>

<details>
<summary><b>Utility Function Command Line Options</b></summary>

The f5acmehandler also supports a set of commandline options:

| **Command Option** | **Description**                                                                                  |
|--------------------|--------------------------------------------------------------------------------------------------|
| --force            | Overrides the default certificate renewal threshhold check (default 30 days)                     |
| --domain           | Performs Acme renewal functions for a single specified domain. Can be combined with --force<br />Examples:<br />--domain www.foo.com<br />--domain www.bar.com --force      |
| --init             | Performs validation checks. Use this command after modifying the global configuration data group<br />- Checks for certificate associate to a client SSL profile<br />- Checks for client SSL profile association to an HTTPS virtual server<br />- Checks for HTTP VIP listening on same HTTPS virtual server IP<br />- Creates HTTP VIP is HTTPS VIP exists<br />- Registers any newly-defined Acme providers |                                                                
| --help             | Shows the help information for above command options                                             |



</details>

<details>
<summary><b>Scheduling Options</b></summary>
</details>

<details>
<summary><b>Miscellaneous Configuration Options</b></summary>
</details>

<br />

------------
### ${\textbf{\color{blue}Acme\ Protocol\ Flow}}$
Blah

<details>
<summary><b>Acme Protocol Flow Diagram</b></summary>
</details>

<br />

------------
### ${\textbf{\color{blue}Additional\ Configuration\ Options}}$
Blah

<details>
<summary><b>External Account Binding (EAB)</b></summary>
</details>

<details>
<summary><b>OCSP and Periodic Revocation Testing</b></summary>
</details>

<details>
<summary><b>BIG-IQ Support</b></summary>
</details>

<br />

------------
### ${\textbf{\color{blue}Testing}}$
Blah

<br />

------------
### ${\textbf{\color{blue}Credits}}$
Blah

<br />


------------
------------


* The Dehydrated Acme client is installed in a local BIG-IP working directory and scheduled to run at specified intervals (on the Active BIG-IP only).
* When the Acme client is triggered, it generates a series of events that call the **hook_script_f5.sh** Bash script. The first event (deploy_challenge) creates a data group entry based on the Acme server's http-01 challenge. The Acme server will then attempt to verify the challenge. The HTTP request arrives at a port 80 HTTP virtual server, and the attached iRule responds with the challenge information acquired from the data group. The second event (clean_challenge) is triggered after a successful Acme server challenge, and is used to remove the data group entry. A final event (deploy_cert) is then called, which takes the new certificate and private key from the local "certs" working directory, and pushes these into the BIG-IP cert/key store.
* The utility assumes that each BIG-IP cert/key is named as the corresponding domain. For example, if the domain URL is "www.f5labs.com", the certificate and private key are also called "www.f5labs.com".
* The utility will also create a client SSL if missing. It assumes the name "$DOMAIN_clientssl" (ex. www.f5labs.com_clientssl), and will attach the associated certificate and private key. The Acme client utility can therefore run before any applications are created, to create the cert/key and client SSL profile, where the application can then consume the client SSL profile.

Full details on all Acme client capabilities cane be found on the [Dehydrated](https://github.com/dehydrated-io/dehydrated) page.

-----------------

**To install, simply execute the following from a BIG-IP command shell**:
```
curl -s https://raw.githubusercontent.com/kevingstewart/f5acmehandler-bash/main/install.sh | bash
```

This will create the necessary file structure under /shared/acme, pull down the latest Dehydrated script and additional files, and create the required BIG-IP data group and iRule:

```
Files/Folders:
/shared/acme/wellknown/
             dehydrated
             config
             domains.txt
             hook_script_f5.sh

BIG-IP data group: /Common/acme_handler_dg
BIG-IP iRule:      /Common/acme_handler_rule
```

-----------------

After installation, navigate to the /shared/acme folder.

1. Edit the **domains.txt** file and add the set of domain URLs to be renewed via acme. Example:
   ```
   test1.f5labs.com
   test2.f5labs.com
   ```

2. Ensure that a port 80 HTTP virtual server exists that represents each of the applied domain URLs. Apply the **acme_handler_rule** iRule to each of the port 80 HTTP virtual servers. For example, if a BIG-IP virtual server is created for a public facing HTTPS site, you must create a separate port 80 HTTP virtual server with the same destination IP (port 80), and assign an HTTP profile and the **acme_handler_rule** iRule. If a port 80 HTTP virtual server already exists for an application, perhaps as an HTTP-to-HTTPS redirect, then simply attach the **acme_handler_rule** iRule to this virtual server.

3. As noted above, this utility assumes the certificate and key are named as the domain URL (ex. www.f5labs.com), and the client SSL profile as "$DOMAIN_clientssl" (ex. www.f5labs.com_clientssl).

4. The default configuration specifies LetsEncrypt as the Acme CA target. To change that, edit the **config** file and adjust the value for **CA=**:
   ```
   CA="buypass"
   ```

5. Perform an initial registration to the Acme server:
   ```
   ./dehydrated --register --accept-terms
   ```
   If using a non-standard Acme CA, you can specify the CA URL in the registration:
   ```
   ./dehydrated --register --accept-terms --ca "https://172.16.0.25:9000/acme/acme/directory"
   ```

6. Finally, to initiate a request to the Acme server:
   ```
   ./dehydrated -c 
   ```
   If using a non-standard Acme CA, you can specify the URL:
   ```
   ./dehydrated -c --ca "https://172.16.0.25:9000/acme/acme/directory"
   ```
   The Dehydrated client will default to ECC certificates. To switch to RSA certificates, use the **-a rsa** option:
   ```
   ./dehydrated -c -a rsa
   ```
   And to force an update, use the **-x** option:
   ```
   ./dehydrated -c -x
   ```
   This will create a new **certs** folder under the /shared/acme working directory, and a subfolder under this named after each domain URL. Inside each of these will be the certificate (cert.pem), private key (privkey.pem), the issuer CA certificate (chain.pem), and a bundle of all certs, subject and issuer (fullchain.pem). The Acme client calls the deploy_cert event in the hook_script_f5.sh Bash script, and moves the new certificate and private key to the BIG-IP cert/key store.
   
7. To set a schedule...





