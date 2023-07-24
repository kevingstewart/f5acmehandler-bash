## ACME Server Testing

This section describes the setup and configuration of local ACME services for testing. These can and should only be used to demonstrate the functionality of the [f5acmehandler-bash](https://github.com/kevingstewart/f5acmehandler-bash/tree/main) utility.

<br />

<details>
<summary><b>Smallstep Step-CA</b></summary>
  Reference: https://smallstep.com/blog/private-acme-server/
  
  <br />
  
  The minimum requirements for this ACME service are:
  
  * [Docker](https://www.docker.com/)
  * [Docker Compose](https://docs.docker.com/compose/)
  
  The Docker-Compose file creates all of the necessary objects and state, and starts an ACME service listener on port 9000. 
  Also note the following adjustable settings within the compose file:

  * **Rootca certificate and key** - The included self-signed root (f5labs.com) is for testing only, but can be replaced. On
    startup the Step-CA client will use this root CA to issue a new intermediate CA for use in signing the leaf certificates in
    the ACME protocol exchange.
    
  * **Configuration entries** - Ensure the following attributes are to your requirements:
    - --dns=localhost: create as many of these entries as needed to represent this ACME server instance
    - --provisioner="admin@f5labs.com": adjust according to define a provisioner admin user
    - --kty RSA - This specifies the key type for the generated intermediate certificate. If left as ECDSA (default), the ACME server
      can only issue ECC certificates. If set to create an RSA intermediate certificate, it can issue ECC _and_ RSA leaf certificates.
      
  * **Local DNS entries** - Near the bottom of the file is a set of echo statements that insert local DNS entries into /etc/hosts.
    As this is for local testing, and there might not be external DNS references to the URLs requested by the ACME client, this
    section allows you to define the set of URL-to-IP addresses the ACME server will access to complete ACME http-01 challenges

  To start the Step-CA service, execute the following:

  ```
  docker-compose -f docker-compose-smallstep-ca.yaml up -d
  ```
  
  To test, point the ACME client at the **https://\<server-ip\>:9000/acme/acme/directory**. In the f5acmehandler-bash configuration, add an entry to the 
  **acme_config_dg** data group for each domain, with the minimum following key and values:

  ```
  String: <domain>
  Value: --ca https://<server-ip>:9000/acme/acme/directory
  ```

  where \<domain\> is the certificate subject (ex. www.f5labs.com).

  
</details>

<br />

<details>
<summary><b>Pebble</b></summary>
  Reference: https://github.com/letsencrypt/pebble
  
</details>
