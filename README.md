# Simple Dehydrated Acme Utility - for F5 BIG-IP

### A wrapper for the [Dehydrated](https://github.com/dehydrated-io/dehydrated) Acme client to simplify integration with F5 BIG-IP.

This utility provides a simplified ACMEv2 integration to support certificate renewal on the BIG-IP, using the popular Dehydrated Acme client. The implementation follows the below pattern:

* The Dehydrated Acme client is installed in a local BIG-IP working directory and scheduled to run at specified intervals (on the Active BIG-IP only).
* When the Acme client is triggered, it generates a series of events that call the **hook_script_f5.sh** Bash script. The first event (deploy_challenge) creates a data group entry based on the Acme server's http-01 challenge. The Acme server will then attempt to verify the challenge. The HTTP request arrives at a port 80 HTTP virtual server, and the attached iRule responds with the challenge information acquired from the data group. The second event (clean_challenge) is triggered after a successful Acme server challenge, and is used to remove the data group entry. A final event (deploy_cert) is then called, which takes the new certificate and private key from the local "certs" working directory, and pushes these into the BIG-IP cert/key store.
* The utility assumes that each BIG-IP cert/key is named as the corresponding domain. For example, if the domain URL is "www.f5labs.com", the certificate and private key are also called "www.f5labs.com".
* The utility will also create a client SSL if missing. It assumes the name "$DOMAIN_clientssl" (ex. www.f5labs.com_clientssl), and will attach the associated certificate and private key. The Acme client utility can therefore run before any applications are created, to create the cert/key and client SSL profile, where the application can then consume the client SSL profile.

Full details on all Acme client capabilities cane be found on the [Dehydrated](https://github.com/dehydrated-io/dehydrated) page.

-----------------

To install, simply execute the following from a BIG-IP command shell:
```
curl -s https://raw.githubusercontent.com/kevingstewart/simple-dehydrated-acme/main/install.sh | bash
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





