# Polyspace Access in Kubernetes

This repository contains utilities for deploying Polyspace&reg; Access&trade; on a Kubernetes&reg; cluster.

## Introduction

This guide explains how to deploy Polyspace Access onto your Kubernetes cluster.
Polyspace Access is a centralized web interface for managing C/C++ static analysis results.
Upload findings, triage defects, track code quality trends, and generate reports across your team.

The repository provides a production-ready Helm&reg; chart that packages all the Kubernetes resources needed to run Polyspace Access as a set of containerized services.
The chart supports internal or external PostgreSQL databases, Lightweight Directory Access Protocol (LDAP) or Security Assertion Markup Language (SAML) authentication, and optional Issue Tracker integration (Jira, Polarion, or Redmine).

For more information on Polyspace Access, see the MathWorks&reg; documentation on [Polyspace Access](https://www.mathworks.com/help/polyspace_access/index.html).

## Requirements

Before you start, you need the following:
- A running Kubernetes cluster that meets the following conditions:
  - Validated against Amazon EKS and Azure AKS clusters.
  - Has an NGINX Ingress Controller installed and configured for external access.
  - Has adequate storage. The Polyspace Access database, ETL, and web server components each request 32GB of memory by default.
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed on your computer and configured to access your Kubernetes cluster.
- [Helm](https://helm.sh/docs/intro/install/) version 3 or later installed on your computer.
- A Polyspace Access license file. To obtain a license, contact [MathWorks Sales](https://www.mathworks.com/company/aboutus/contact_us/contact_sales.html).
- Docker images for Polyspace Access, available from the MathWorks [download page](https://www.mathworks.com/downloads/).

> **Note:** This describes one supported deployment approach. Adapt the steps as needed to match your environment.

## Configuration Overview

The following table summarizes which values you must configure for each deployment option. Values marked as common are required regardless of the options you choose.

| Option | Required Values | Notes |
|---|---|---|
| **Common (all options)** | `global.ingress.host`, `polyspaceAccess.webServer.license.secretName`, `usermanager.server.authPrivateKey.secret.name`, `usermanager.server.config.adminIds`, `usermanager.server.config.adminInitialPassword` | Required for every installation. You must also create the license and auth private key Secrets before installing. |
| **Internal DB** | `polyspaceAccess.db.passwordString` (or `passwordSecret`), `usermanager.server.config.db.username`, `usermanager.server.config.db.password` | The chart deploys PostgreSQL containers. No external DB setup required. |
| **External DB** | `polyspaceAccess.db.external.enabled`, `.host`, `.port`, `.passwordSecret`, `usermanager.db.external.enabled`, `.host`, `.port`, `usermanager.server.config.db.username`, `.password`, `.sslEnabled` | You must provision and initialize the databases before installing. |
| **LDAP authentication** | `usermanager.server.config.providers[]` (type, credentials, url, searchOptions) | Provide bind credentials and search configuration for your LDAP directory. |
| **SAML + LDAP** | `usermanager.server.config.saml.enabled`, `.metadataUrl`, `.relyingParty`, `.binding`, `.corsDomain`, `.user.*`, plus the LDAP `providers[]` array | LDAP is required alongside SAML for user synchronization. |
| **Internal authentication (no external identity provider)** | (no additional values) | Users are managed through the User Manager Dashboard. No LDAP or SAML configuration needed. |
| **Issue Tracker** | `issuetracker.enabled`, `issuetracker.server.provider`, `issuetracker.server.config.*` (or `configSecret`) | Optional. Configure only if you want to integrate with Jira, Polarion, or Redmine. |
| **Private image registry** | `global.image.registry`, `global.image.pullSecrets[]` | Required if images are hosted in a private container registry rather than loaded locally. |
| **TLS / HTTPS** | `global.ingress.tls.enabled`, `global.ingress.tls.secretName` | Provide a Kubernetes TLS Secret with your certificate and key. |

## Deployment Steps

### Create Namespace

Kubernetes uses namespaces to separate groups of resources.
To isolate the Polyspace Access deployment from other resources on the cluster, create a dedicated namespace.

For example, to create a namespace called `polyspace`:
```
kubectl create namespace polyspace
```

The commands in this guide use `polyspace` as the namespace.
Substitute `polyspace` with your namespace when using these commands.

### Create Persistent Volumes

Polyspace Access uses *PersistentVolumes* to retain data beyond the lifetime of Kubernetes pods.
It is recommended to provision volumes externally and manage them outside of the Helm chart.

Create a PersistentVolumeClaim for each of the following:

| PVC Name (default) | values.yaml Key | Purpose | Access Mode | Min. Size |
|---|---|---|---|---|
| `polyspace-access-db` | `volumes.polyspaceAccess.db.claimName` | PostgreSQL data for the Polyspace Access database (not required if using an external database) | ReadWriteOnce | 10Gi |
| `usermanager-db` | `volumes.usermanager.db.claimName` | PostgreSQL data for the User Manager database (not required if using an external database) | ReadWriteOnce | 1Gi |
| `polyspace-access-storage` | `volumes.polyspaceAccess.etl.claimName.storage` | Persistent storage for processed analysis results | ReadWriteOnce | 50Gi |
| `polyspace-access-working` | `volumes.polyspaceAccess.etl.claimName.working` | Temporary working directory for ETL processing | ReadWriteOnce | 10Gi |
| `polyspace-access-invalid` | `volumes.polyspaceAccess.etl.claimName.invalid` | Results that failed validation or import | ReadWriteOnce | 50Gi |
| `polyspace-access-upload` | `volumes.polyspaceAccess.etl.claimName.upload` | Staging area for uploaded results (shared by web server and ETL) | ReadWriteMany | 10Gi |
| `polyspace-access-temp-upload` | `volumes.polyspaceAccess.webServer.claimName.tempUpload` | Temporary storage for in-progress uploads | ReadWriteOnce | 10Gi |
| `polyspace-access-download` | `volumes.polyspaceAccess.webServer.claimName.download` | Files prepared for user download | ReadWriteOnce | 10Gi |

You can create a PersistentVolumeClaim using the following example configuration file.
Replace `<namespace>` with the namespace for Polyspace Access, `<pvc-name>` with the PersistentVolumeClaim name, `<access-mode>` with the required access mode, and `<capacity>` with the storage size.
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <pvc-name>
  namespace: <namespace>
spec:
  accessModes:
    - <access-mode>
  storageClassName: <storage-class-name>
  resources:
    requests:
      storage: <capacity>
```

Apply the PVC:
```
kubectl apply -f <pvc-file>.yaml
```

After creating all PVCs, verify they are bound:
```
kubectl get pvc -n polyspace
```
All PVCs must show a status of `Bound` before you run `helm install`.

> **Note:** Size the `polyspace-access-storage` and `polyspace-access-upload` volumes based on the number and size of analysis results you expect to store. A single Polyspace analysis result can range from a few megabytes to several gigabytes depending on the codebase size.

> **Note:** If you use the internal PostgreSQL database containers, configure `subPath` for the database PVCs (`polyspace-access-db` and `usermanager-db`). PostgreSQL requires an empty directory to initialize. A newly created PVC might contain a `lost+found` directory that prevents PostgreSQL from starting.

> **Note:** The `polyspace-access-upload` PVC requires `ReadWriteMany` access because it is shared by the web server and ETL services. The provisioning of `ReadWriteMany` volumes is platform-specific. Consult your cloud provider documentation for instructions.

Alternatively, for development environments, you can let the Helm chart create PVCs automatically by setting `global.volume.storageClassName` in your `values.yaml`:
```yaml
global:
  volume:
    create: true
    storageClassName: standard
```

> **Caution:** Depending on the reclaim policy of the StorageClass, deleting the Helm release might delete the PersistentVolumes and all stored data. For production deployments, use pre-provisioned volumes instead.

#### Using Custom PVC Names

If your PVCs use names that differ from the defaults, update the `volumes` section in your `values.yaml`:
```yaml
volumes:
  usermanager:
    db:
      claimName: my-um-db-pvc
  polyspaceAccess:
    db:
      claimName: my-psaccess-db-pvc
    etl:
      claimName:
        storage: my-etl-storage
        invalid: my-etl-invalid
        working: my-etl-working
        upload: my-etl-upload
    webServer:
      claimName:
        tempUpload: my-temp-upload
        download: my-download
```

### Create Kubernetes Secrets

The installation requires a Kubernetes Secret containing sensitive configuration including the license file, authentication private key, and database passwords.

#### Generate the Authentication Private Key

The User Manager service requires an RSA private key for signing authentication tokens:
```
openssl genrsa -out auth-private-key.pem 2048
```
The private key must not be password-protected. Do not reuse the private key that you use to generate SSL/TLS certificates. Restrict access to this key to administrators only.

#### Populate and Apply the Secrets

A template file `docs/secrets.yaml` is provided with the Helm chart. Edit it and insert your values:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: polyspace-access
  namespace: polyspace
stringData:
  auth-private-key.pem: |
    -----BEGIN RSA PRIVATE KEY-----
    <contents of your generated private key>
    -----END RSA PRIVATE KEY-----
  license.lic: |
    <contents of your Polyspace Access license file>
  ps-db-password: <your-polyspace-db-password>
  um-db-password: <your-usermanager-db-password>
  config-issuetracker.json: |
    <optional: issue tracker configuration JSON>
```

Apply the Secret:
```
kubectl apply -f docs/secrets.yaml -n polyspace
```

Verify the Secret was created:
```
kubectl get secret polyspace-access -n polyspace
```

| Key | Description | Required |
|---|---|---|
| `auth-private-key.pem` | RSA private key for User Manager token signing | Yes |
| `license.lic` | Polyspace Access license key content | Yes |
| `ps-db-password` | Password for the Polyspace Access database role (`prs_data`) | Yes |
| `um-db-password` | Password for the User Manager database role | Yes |
| `config-issuetracker.json` | Issue Tracker provider configuration in JSON format | No |

To keep your Kubernetes Secrets secure, enable encryption at rest and restrict access to your namespace using role-based access control.
For more information, see the Kubernetes documentation for [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/).

### Create Helm Values File

Create a YAML file containing configuration parameters for Polyspace Access.
Copy the following lines into a YAML file, `values.yaml`, and modify the values for your environment:
```yaml
global:
  ingress:
    host: polyspace.example.com
    tls:
      enabled: true
      secretName: tls-polyspace

usermanager:
  server:
    config:
      adminIds:
      - admin
      adminInitialPassword: <your-admin-password>
      db:
        username: um
        password: <your-um-db-password>

polyspaceAccess:
  db:
    passwordString: <your-polyspace-db-password>
```

Modify the following values:
- `global.ingress.host` &mdash; Specify the hostname for external access to Polyspace Access. Must be a DNS name; IP addresses are not accepted.
- `global.ingress.tls.enabled` &mdash; Set to `true` to enable HTTPS. You must provide a TLS Secret.
- `global.ingress.tls.secretName` &mdash; Specify the name of a Kubernetes TLS Secret containing your certificate and key.
- `usermanager.server.config.adminIds` &mdash; Specify which user IDs are granted administrator privileges.
- `usermanager.server.config.adminInitialPassword` &mdash; Specify the initial password for administrator accounts.
- `usermanager.server.config.db.username` &mdash; Specify the PostgreSQL role for the User Manager database.
- `usermanager.server.config.db.password` &mdash; Specify the password for the User Manager database role.
- `polyspaceAccess.db.passwordString` &mdash; Specify the password for the Polyspace Access database role (`prs_data`). Alternatively, use `polyspaceAccess.db.passwordSecret` to reference a Kubernetes Secret.

You can also combine multiple override files. Later files take precedence:
```
helm upgrade --install polyspace . -f values.yaml -f values-external-db.yaml -f values-ldap.yaml
```

For a full list of configurable Helm values, see the [Helm Values Reference](#helm-values-reference) section.

### Load Docker Images

Download the Polyspace Access Docker images from the MathWorks [download page](https://www.mathworks.com/downloads/). Retag and upload the images to your container registry:
```
# Example: load, retag, and push images
docker load -i <image>.tar
docker tag <image> <your-registry>/<image>:<tag>
docker push <your-registry>/<image>:<tag>
```

If using a private registry, configure the registry in your `values.yaml`:
```yaml
global:
  image:
    registry: your-registry.example.com
    pullSecrets:
    - name: my-registry-secret
```

Alternatively, use the provided `docs/load-images.sh` script to load, retag, and push images to your registry.

### Install Helm Chart

Navigate to the chart directory (the folder containing `Chart.yaml`) and install the Polyspace Access Helm chart with your custom values file:
```
helm upgrade --install polyspace . --namespace polyspace
```

Check the status of the Polyspace Access pods:
```
kubectl get pods -n polyspace
```
When all pods display `1/1` in the `READY` field, Polyspace Access is ready to use.
The output of the `kubectl get pods` command looks something like this when Polyspace Access is ready:
```
NAME                                          READY   STATUS    RESTARTS   AGE
polyspace-access-db-xxxxx                     1/1     Running   0          2m
polyspace-access-etl-xxxxx                    1/1     Running   0          2m
polyspace-access-web-server-xxxxx             1/1     Running   0          2m
polyspace-usermanager-authnz-xxxxx            1/1     Running   0          2m
polyspace-usermanager-db-xxxxx                1/1     Running   0          2m
polyspace-usermanager-server-xxxxx            1/1     Running   0          2m
polyspace-usermanager-ui-xxxxx                1/1     Running   0          2m
```

### Verify the Deployment

Access the Polyspace Access web interface by navigating to:
```
https://<HOST>:<PORT>/authn/signin
```
where `HOST` and `PORT` correspond to your Ingress configuration.

Log in with the administrator credentials you specified in the `values.yaml` file.

To manage users and groups, open the User Manager Dashboard at:
```
https://<HOST>:<PORT>/um/ui/dashboard
```

#### Application URLs

| Route | URL | Purpose |
|---|---|---|
| Polyspace Access Login | `https://<HOST>:<PORT>/authn/signin` | User authentication and login interface |
| User Manager Dashboard | `https://<HOST>:<PORT>/um/ui/dashboard` | Web-based interface for managing user accounts, roles, and permissions |

## Upgrade Polyspace Access

To upgrade Polyspace Access in a Kubernetes cluster:

1. Back up your databases before upgrading. If you use internal database containers, back up the PersistentVolumes. If you use external databases, use your database management tool to create a backup. Also back up your `values.yaml` file.

2. Review [Breaking Changes](#breaking-changes) for any changes that require updates to your `values.yaml` file.

3. Get the Helm charts that correspond to the target Polyspace Access version.

4. Download the updated Docker images from the MathWorks [download page](https://www.mathworks.com/downloads/) and upload them to your cluster.

5. Navigate to the folder containing the Helm charts and run:
   ```
   helm upgrade --install polyspace . --namespace polyspace
   ```

6. Monitor the status of your pods:
   ```
   kubectl get pods -n polyspace
   ```
   Verify that all pods reach a `Running` state.

## Uninstall Polyspace Access

To uninstall the Polyspace Access Helm chart from your Kubernetes cluster:
```
helm uninstall polyspace --namespace polyspace
```

Delete the Secrets:
```
kubectl delete secret polyspace-access --namespace polyspace
```

> **Note:** Uninstalling the Helm chart does not delete PersistentVolumeClaims. Your data remains intact unless you manually delete the PVCs or the StorageClass reclaim policy is set to `Delete`.

## Advanced Setup Steps

### Configure External Database

By default, the Helm chart deploys internal PostgreSQL containers. To connect to your own managed PostgreSQL instances (Amazon RDS, Azure Database for PostgreSQL, or self-hosted), configure external databases.

#### Prerequisites

Create two databases on your PostgreSQL server:

**Polyspace Access Database:**
```sql
-- Connect as a PostgreSQL superuser
CREATE ROLE prs_data WITH LOGIN PASSWORD 'your-password';
ALTER ROLE prs_data CREATEDB;
CREATE DATABASE prs_data OWNER prs_data;
```

**User Manager Database:**
```sql
CREATE ROLE um WITH LOGIN PASSWORD 'your-password';
CREATE DATABASE umdb OWNER um;

\c umdb

CREATE TABLE identity(
  id text NOT NULL CHECK (id <> ''),
  source text NOT NULL CHECK (source <> ''),
  type text NOT NULL CHECK (type <> ''),
  display_name text,
  email text,
  image_uri text,
  PRIMARY KEY (id, source)
);

CREATE TABLE password(
  id text NOT NULL,
  source text NOT NULL,
  password text NOT NULL,
  PRIMARY KEY (id, source),
  FOREIGN KEY (id, source) REFERENCES identity(id, source) ON DELETE CASCADE
);
```

#### values.yaml Configuration

**Polyspace Access Database:**
```yaml
polyspaceAccess:
  db:
    external:
      enabled: true
      host: your-db-host.example.com
      port: 5432
      passwordSecret:
        name: polyspace-access
        key: ps-db-password
```

**User Manager Database:**
```yaml
usermanager:
  db:
    external:
      enabled: true
      host: your-db-host.example.com
      port: 5432
  server:
    config:
      db:
        username: um
        password: your-password
        sslEnabled: true
```

For all external database properties, see [Helm Values Reference](#helm-values-reference).

> **Note:** The User Manager database password is specified in plaintext in `values.yaml`. Store your values file securely and restrict access.

#### SSL Configuration for External Databases

When connecting to a managed database service (Amazon RDS, Azure Database for PostgreSQL, Google Cloud SQL), enable SSL to encrypt the connection.

When `sslEnabled` is true and your database uses a certificate signed by a private certificate authority (CA) (common with Amazon RDS), provide the CA certificate:
```
kubectl create secret generic tls-um --from-file=ca-certificates.crt=/path/to/ca.pem -n polyspace
```
```yaml
usermanager:
  server:
    tls:
      enabled: true
      ca:
        secretName: tls-um
        key: ca-certificates.crt
```

#### Complete External Database Example

The following example shows a complete `values-external-db.yaml` override file that configures both databases to use external instances:
```yaml
usermanager:
  db:
    external:
      enabled: true
      host: psaccess-db.abc123.us-east-1.rds.amazonaws.com
      port: 5432
  server:
    config:
      db:
        username: um
        password: changeme
        sslEnabled: true
    tls:
      enabled: true
      ca:
        secretName: tls-um
        key: ca-certificates.crt

polyspaceAccess:
  db:
    external:
      enabled: true
      host: psaccess-db.abc123.us-east-1.rds.amazonaws.com
      port: 5433
      passwordSecret:
        name: polyspace-access-db-secret
        key: password
```

Install using the override file:
```
helm upgrade --install polyspace . -f values-external-db.yaml -n polyspace
```

### Configure LDAP Authentication

To authenticate users against an LDAP directory, configure the `usermanager.server.config.providers` array:
```yaml
usermanager:
  server:
    config:
      providers:
      - type: ldap
        syncIntervalNanoSeconds: 1800000000000
        properties:
          credentials:
            bindDN: cn=admin,dc=example,dc=com
            bindPassword: password
          url: ldap://your-ldap-server:389
          searchOptions:
            user:
              filter: (&(objectClass=inetOrgPerson))
              searchBaseDN: dc=example,dc=com
              schema:
                id: uid
                displayName: displayName
                email: mail
                image: ""
                member: memberOf
            group:
              enabled: false
              filter: (objectClass=groupOfNames)
              searchBaseDN: dc=example,dc=com
              schema:
                id: cn
                displayName: cn
                email: ""
                image: ""
                member: member
          generalOptions:
            paginate: true
            pageSize: 1000
```

For all LDAP properties, see [Helm Values Reference](#helm-values-reference).

#### LDAP over TLS (LDAPS)

For LDAP over TLS, use an `ldaps://` URL and provide the CA certificate:
```
kubectl create secret generic tls-um --from-file=ca-certificates.crt=/path/to/ldap-ca.pem -n polyspace
```

If the certificate chain includes intermediate certificates, combine the root and intermediate certificates into a single PEM file before creating the Secret.

```yaml
usermanager:
  server:
    config:
      providers:
      - type: ldap
        properties:
          url: ldaps://your-ldap-server:636
          # ... remaining LDAP properties
    tls:
      enabled: true
      ca:
        secretName: tls-um
        key: ca-certificates.crt
```

#### Active Directory Example

The following example shows a typical configuration for Microsoft Active Directory:
```yaml
usermanager:
  server:
    config:
      providers:
      - type: ldap
        syncIntervalNanoSeconds: 1800000000000
        properties:
          credentials:
            bindDN: cn=svc-polyspace,ou=ServiceAccounts,dc=corp,dc=example,dc=com
            bindPassword: ServiceAccountPassword
          url: ldaps://ad.corp.example.com:636
          searchOptions:
            user:
              filter: (&(objectClass=user)(objectCategory=person))
              searchBaseDN: ou=Users,dc=corp,dc=example,dc=com
              schema:
                id: sAMAccountName
                displayName: displayName
                email: mail
                image: ""
                member: memberOf
            group:
              enabled: true
              filter: (objectClass=group)
              searchBaseDN: ou=Groups,dc=corp,dc=example,dc=com
              schema:
                id: cn
                displayName: cn
                email: ""
                image: ""
                member: member
          generalOptions:
            paginate: true
            pageSize: 1000
    tls:
      enabled: true
      ca:
        secretName: tls-um
        key: ca-certificates.crt
```

### Configure SAML Authentication

SAML enables Single Sign-On (SSO) with an external identity provider. When SAML is enabled, users authenticate through the login page of your identity provider rather than entering credentials directly in Polyspace Access.

SAML requires an LDAP provider to also be configured. The LDAP provider handles user synchronization &mdash; it populates the user directory so that permissions and group membership can be managed and so that results can be assigned to users for review. SAML handles only authentication (login), not user discovery.

Configuring SAML has these prerequisites:
- Your identity provider follows the SAML protocol.
- You have access to your identity provider. Contact your identity management administrator to obtain access.
- Your identity provider hosts an endpoint for the SAML metadata XML.

Users that you manually add to the User Manager dashboard cannot authenticate through the SSO service. You must add these users to your identity provider for SSO to authenticate their login.

```yaml
usermanager:
  server:
    config:
      saml:
        enabled: true
        metadataUrl: https://your-idp.example.com/metadata.xml
        relyingParty: https://polyspace.example.com
        binding: "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
        corsDomain: https://your-idp.example.com
        user:
          id: uname
          displayName: uname
          email: email
          image: image
      providers:
      - type: ldap
        # ... LDAP configuration for user sync
```

For all SAML properties, see [Helm Values Reference](#helm-values-reference).

When registering Polyspace Access as a Service Provider in your identity provider:

| Field | Value |
|---|---|
| Entity ID / Audience URI | Same value as `saml.relyingParty` |
| Assertion Consumer Service (ACS) URL | `https://<your-host>/authnz/saml/saml/acs` |
| Single Logout (SLO) URL | `https://<your-host>/authnz/saml/saml/slo` |
| Name ID Format | `urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified` |

Ensure that the SAML assertion includes attributes that match the values configured in `saml.user.*`. The `saml.user.id` attribute value must match the user ID that the LDAP provider synchronizes.

### Configure Internal Authentication

If you do not configure an LDAP provider or enable SAML, the User Manager uses its internal user store. Users are created manually through the User Manager Dashboard.

With internal authentication, configure administrator accounts and their initial password:
```yaml
usermanager:
  server:
    config:
      adminIds:
      - admin
      adminInitialPassword: your-secure-password
```

The `adminIds` list specifies which user IDs are granted administrator privileges. The `adminInitialPassword` sets the password for these accounts on first installation.

### Configure Issue Tracker

The Issue Tracker service integrates Polyspace Access with an external bug tracking system so that users can create and link issues directly from analysis findings. By default, the Issue Tracker is disabled.

Supported providers: **Jira** (Server, Cloud, or Data Center), **Polarion**, and **Redmine**.

You can provide the Issue Tracker configuration inline in `values.yaml` or reference a Kubernetes Secret that contains a configuration JSON file. Use a Secret for production deployments to keep credentials out of the values file. If both `configSecret` and inline `config` are provided, the Secret takes precedence.

#### Jira Configuration

Jira supports multiple deployment types and authentication methods. Set `issuetracker.server.provider` to `jira` and configure the appropriate `config` block.

**Jira Server with Cookie Authentication:**
```yaml
issuetracker:
  enabled: true
  server:
    provider: jira
    config:
      url: https://jira.example.com
      jiraType: server
      authnMethod: cookie
```

With cookie authentication, users enter their Jira credentials in the Polyspace Access web interface. The service uses a session cookie for later requests.

**Jira Server with OAuth1:**
```yaml
issuetracker:
  enabled: true
  server:
    provider: jira
    config:
      url: https://jira.example.com
      jiraType: server
      authnMethod: oauth1
      authnConfig:
        consumerKey: your-consumer-key
        callbackBaseURL: https://polyspace.example.com
        privateKeyPath: /path/to/private-key.pem
```

Register an Application Link in Jira with the consumer key and public key. The `callbackBaseURL` must match the base URL of your Polyspace Access instance. The hostname that you specify when you create the private key must match the hostname in `callbackBaseURL`. If the hostnames do not match, users get an authentication error when they attempt to create Jira tickets from Polyspace Access.

**Jira Cloud with OAuth1:**
```yaml
issuetracker:
  enabled: true
  server:
    provider: jira
    config:
      url: https://your-domain.atlassian.net
      jiraType: cloud
      authnMethod: oauth1
      authnConfig:
        consumerKey: your-consumer-key
        callbackBaseURL: https://polyspace.example.com
        privateKeyPath: /path/to/private-key.pem
```

**Jira Cloud with OAuth2:**
```yaml
issuetracker:
  enabled: true
  server:
    provider: jira
    config:
      url: https://your-domain.atlassian.net
      jiraType: cloud
      authnMethod: oauth2
      authnConfig:
        clientId: your-client-id
        clientSecret: your-client-secret
        redirectURL: https://polyspace.example.com/issuetracker/oauth2/callback
        scopes:
        - read:jira-work
        - read:jira-user
        - write:jira-work
        siteURL: https://your-domain.atlassian.net
```

Create an OAuth 2.0 integration in the Atlassian Developer Console. Set the callback URL to `https://<your-host>/issuetracker/oauth2/callback`. The `scopes` list must include, at minimum: `read:jira-work`, `read:jira-user`, and `write:jira-work`.

**Jira Data Center with OAuth1:**
```yaml
issuetracker:
  enabled: true
  server:
    provider: jira
    config:
      url: https://jira-dc.example.com
      jiraType: dataCenter
      authnMethod: oauth1
      authnConfig:
        consumerKey: your-consumer-key
        callbackBaseURL: https://polyspace.example.com
        privateKeyPath: /path/to/private-key.pem
```

**Jira Data Center with OAuth2:**
```yaml
issuetracker:
  enabled: true
  server:
    provider: jira
    config:
      url: https://jira-dc.example.com
      jiraType: dataCenter
      authnMethod: oauth2
      authnConfig:
        clientId: your-client-id
        clientSecret: your-client-secret
        redirectURL: https://polyspace.example.com/issuetracker/oauth2/callback
```

For all Jira configuration properties, see [Helm Values Reference](#helm-values-reference).

#### Polarion Configuration

```yaml
issuetracker:
  enabled: true
  server:
    provider: polarion
    config:
      url: https://polarion.example.com
      apiKey: your-api-key
```

To obtain the `apiKey`, log in to Polarion as a dedicated API account with admin-level privileges, click *My account* in the settings menu, then select *Personal Access Token* from the toolbar.

#### Redmine Configuration

```yaml
issuetracker:
  enabled: true
  server:
    provider: redmine
    config:
      url: https://redmine.example.com
      apiKey: your-api-key
```

To obtain the `apiKey`, log in to Redmine as a dedicated API account with admin-level privileges, click *My account*, then click *Show* under API access key.

For all Issue Tracker properties, see [Helm Values Reference](#helm-values-reference).

#### Using a Kubernetes Secret for Issue Tracker Configuration

For production deployments, store the Issue Tracker configuration in a Kubernetes Secret rather than inline in `values.yaml`. This keeps credentials (API keys, client secrets) out of version control.

Create a JSON file with the provider configuration:
```json
{
  "url": "https://jira.example.com",
  "jiraType": "server",
  "authnMethod": "oauth1",
  "authnConfig": {
    "consumerKey": "your-consumer-key",
    "callbackBaseURL": "https://polyspace.example.com",
    "privateKeyPath": "/app/keys/jira-private-key.pem"
  }
}
```

Create the Secret:
```
kubectl create secret generic polyspace-access \
  --from-file=config-issuetracker.json=/path/to/config.json \
  -n polyspace
```

Reference the Secret in your `values.yaml`:
```yaml
issuetracker:
  enabled: true
  server:
    provider: jira
    configSecret:
      name: polyspace-access
      key: config-issuetracker.json
```

### Configure Resource Requests and Limits

Each service component supports `resources.requests` and `resources.limits` for CPU and memory. The following table lists the defaults:

| Component | CPU Request | Memory Request | Memory Limit |
|---|---|---|---|
| `usermanager.db` | 125m | 100Mi | 250Mi |
| `usermanager.authnz` | 125m | 100Mi | 250Mi |
| `usermanager.server` | 125m | 100Mi | 250Mi |
| `usermanager.ui` | 125m | 100Mi | 250Mi |
| `issuetracker.server` | 125m | 100Mi | 250Mi |
| `issuetracker.ui` | 125m | 100Mi | 250Mi |
| `polyspaceAccess.db` | 4 | 32Gi | 32Gi |
| `polyspaceAccess.etl` | 4 | 32Gi | 32Gi |
| `polyspaceAccess.webServer` | 4 | 32Gi | 32Gi |

Adjust the `polyspaceAccess` component limits based on the number of concurrent users and the size of analysis results being processed. The User Manager and Issue Tracker services are lightweight and typically do not require adjustment.

### Cloud-Specific Configuration

When installing on a managed Kubernetes service, adjust the following settings:
- Set `global.image.registry` to your cloud container registry (for example, `myregistry.azurecr.io`).
- Set `global.volume.storageClassName` to a StorageClass provided by your cloud provider (for example, `managed` for AKS).
- Configure `global.image.pullSecrets` to authenticate with your cloud registry.
- Configure Ingress annotations for your cloud load balancer (for example, `kubernetes.io/ingress.class: azure/application-gateway` for AKS Application Gateway).

## Troubleshooting

### Pods Stuck in Pending State

If pods remain in `Pending` state, the cluster might not have enough resources or PVCs cannot be bound.

Check PVC status:
```
kubectl get pvc -n polyspace
```
If a PVC is in `Pending` state, check that the StorageClass exists and that the storage provisioner is available.

Check pod details:
```
kubectl describe pod <pod-name> -n polyspace
```

### Pods in CrashLoopBackOff

This typically indicates a service configuration error or missing secrets.

Check logs from the crashed container:
```
kubectl logs <pod-name> -n polyspace --previous
```

Verify that all required Secrets exist:
```
kubectl get secret polyspace-access -n polyspace
```

### Cannot Access Web Interface

Verify Ingress configuration:
```
kubectl get ingress -n polyspace
```

Confirm that the Ingress controller pods are running:
```
kubectl get pods -n ingress-nginx
```

Confirm `global.ingress.host` resolves to the cluster.

### LDAP Authentication Fails

Check the User Manager server logs for authentication errors:
```
kubectl logs -l app.kubernetes.io/component=usermanager-server -n polyspace
```

Verify the LDAP URL is reachable from inside the cluster. For LDAPS, verify that the CA certificate Secret is correctly configured.

### Upload Fails with 413 Error

The NGINX Ingress controller has a default body size limit. Set the following annotation in your `values.yaml`:
```yaml
global:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/proxy-body-size: "0"
```

### Collect Diagnostic Information

To collect logs from all Polyspace Access pods:
```
kubectl logs -l app.kubernetes.io/instance=polyspace -n polyspace --all-containers
```

When contacting MathWorks Technical Support, provide:
1. Polyspace Access release version (for example, R2026b)
2. Helm chart version
3. Description of the symptom or error
4. Your `values.yaml` file with sensitive information (passwords, keys) masked
5. Logs from all pods
6. Output of `kubectl describe` for all deployments or pods

## Helm Values Reference

The following tables describe all configurable properties in the `values.yaml` file, organized by category.

### Global Settings

| Property | Description | Default | Required |
|---|---|---|---|
| `global.debug` | Enable debug-level logging for all services. | `false` | No |
| `global.image.registry` | Container registry to pull images from. Leave empty to use locally loaded images. | (empty) | If using private registry |
| `global.image.pullPolicy` | Kubernetes image pull policy. Values: `IfNotPresent`, `Always`, `Never`. | `IfNotPresent` | No |
| `global.image.pullSecrets` | List of Kubernetes Secrets of type `kubernetes.io/dockerconfigjson` for registry authentication. | `[]` | If using private registry |
| `global.ingress.controllerName` | Ingress controller type. | `nginx` | No |
| `global.ingress.annotations` | Annotations applied to the Ingress resource. Use this to configure controller-specific behavior (for example, proxy body size limits). | `{}` | No |
| `global.ingress.host` | Hostname for external access. Must be a DNS name &mdash; IP addresses are not accepted. | &mdash; | Yes |
| `global.ingress.url` | Full Ingress URL including protocol. If not provided, defaults to `https://<host>`. | (derived from host) | No |
| `global.ingress.tls.enabled` | Enable TLS on the Ingress. | `false` | No |
| `global.ingress.tls.secretName` | Name of the Kubernetes TLS Secret containing the certificate and private key. | &mdash; | If TLS enabled |
| `global.volume.create` | If `true`, the chart creates PVCs automatically using the specified StorageClass. | `false` | No |
| `global.volume.storageClassName` | StorageClass for auto-created PVCs. Also triggers PVC creation if set (even when `create` is not explicitly `true`). | &mdash; | If create is true |

### Image Settings

| Property | Description | Default |
|---|---|---|
| `images.usermanager.tag` | Image tag for all User Manager service images. | (chart default) |
| `images.usermanager.dbImage` | Image name for the User Manager database container. | (chart default) |
| `images.usermanager.serverImage` | Image name for the User Manager server container. | (chart default) |
| `images.usermanager.authnzImage` | Image name for the User Manager AuthNZ container. | (chart default) |
| `images.usermanager.uiImage` | Image name for the User Manager web UI container. | (chart default) |
| `images.issuetracker.tag` | Image tag for all Issue Tracker service images. | (chart default) |
| `images.issuetracker.serverImage` | Image name for the Issue Tracker server container. | (chart default) |
| `images.issuetracker.uiImage` | Image name for the Issue Tracker web UI container. | (chart default) |
| `images.polyspaceAccess.tag` | Image tag for all Polyspace Access service images. | (chart default) |
| `images.polyspaceAccess.dbImage` | Image name for the Polyspace Access database container. | (chart default) |
| `images.polyspaceAccess.etlImage` | Image name for the Polyspace Access ETL container. | (chart default) |
| `images.polyspaceAccess.webServerImage` | Image name for the Polyspace Access web server container. | (chart default) |

### Volume Settings

| Property | Description | Default | Required |
|---|---|---|---|
| `volumes.usermanager.db.claimName` | PVC name for the User Manager database data folder. | `usermanager-db` | If using internal DB |
| `volumes.usermanager.db.subPath` | SubPath in the PVC to mount. Use when sharing a single PVC. | &mdash; | No |
| `volumes.polyspaceAccess.db.claimName` | PVC name for the Polyspace Access database data folder. | `polyspace-access-db` | If using internal DB |
| `volumes.polyspaceAccess.db.subPath` | SubPath in the PVC to mount. | &mdash; | No |
| `volumes.polyspaceAccess.etl.claimName.storage` | PVC name for processed analysis results. | `polyspace-access-storage` | Yes |
| `volumes.polyspaceAccess.etl.claimName.invalid` | PVC name for results that failed import. | `polyspace-access-invalid` | Yes |
| `volumes.polyspaceAccess.etl.claimName.working` | PVC name for ETL temporary working folder. | `polyspace-access-working` | Yes |
| `volumes.polyspaceAccess.etl.claimName.upload` | PVC name for uploaded results awaiting processing. | `polyspace-access-upload` | Yes |
| `volumes.polyspaceAccess.etl.subPath.*` | SubPath values (`storage`, `invalid`, `working`, `upload`) for sharing a single PVC across ETL mounts. | &mdash; | No |
| `volumes.polyspaceAccess.webServer.claimName.tempUpload` | PVC name for in-progress upload staging. | `polyspace-access-temp-upload` | Yes |
| `volumes.polyspaceAccess.webServer.claimName.download` | PVC name for files prepared for user download. | `polyspace-access-download` | Yes |
| `volumes.polyspaceAccess.webServer.subPath.*` | SubPath values (`tempUpload`, `download`) for sharing a single PVC across web server mounts. | &mdash; | No |

### User Manager Settings

| Property | Description | Default | Required |
|---|---|---|---|
| `usermanager.db.external.enabled` | Use an external PostgreSQL instance instead of the bundled database container. | `false` | No |
| `usermanager.db.external.host` | Hostname or IP of the external PostgreSQL server. | &mdash; | If external enabled |
| `usermanager.db.external.port` | Port of the external PostgreSQL server. | &mdash; | If external enabled |
| `usermanager.server.config.accessToken.expirationSec` | Duration in seconds of the signed tokens issued to authenticated users. Determines the session lifetime. | `86400` | No |
| `usermanager.server.config.db.username` | PostgreSQL role for the User Manager database. | `um` | Yes |
| `usermanager.server.config.db.password` | Password for the User Manager database role. | &mdash; | Yes |
| `usermanager.server.config.db.timeoutNanoSeconds` | Database connection timeout in nanoseconds. | `20000000000` (20s) | No |
| `usermanager.server.config.db.sslEnabled` | Require SSL for the database connection. Set to `true` for managed services (RDS, Azure). | `false` | No |
| `usermanager.server.config.adminIds` | List of user IDs granted administrator privileges. | `[admin]` | Yes |
| `usermanager.server.config.adminInitialPassword` | Initial password set for admin users on first deployment. | &mdash; | Yes |
| `usermanager.server.config.providers` | Array of LDAP identity provider configurations. See [Configure LDAP Authentication](#configure-ldap-authentication). | &mdash; | If using LDAP |
| `usermanager.server.config.apiKeys` | Map of API keys for programmatic access. Each key maps to a principal (user ID). | &mdash; | No |
| `usermanager.server.config.saml.enabled` | Enable SAML authentication. | `false` | No |
| `usermanager.server.config.saml.metadataUrl` | URL of the SAML metadata XML for the identity provider. | &mdash; | If SAML enabled |
| `usermanager.server.config.saml.relyingParty` | Entity ID / Audience URI registered with the identity provider. | &mdash; | If SAML enabled |
| `usermanager.server.config.saml.binding` | SAML binding method (HTTP-POST or HTTP-Redirect URN). | &mdash; | If SAML enabled |
| `usermanager.server.config.saml.corsDomain` | Origin URL of the identity provider for cross-origin resource sharing (CORS). | &mdash; | If SAML enabled |
| `usermanager.server.config.saml.user.id` | SAML assertion attribute mapping to user ID. | `uname` | If SAML enabled |
| `usermanager.server.config.saml.user.displayName` | SAML assertion attribute mapping to display name. | `uname` | If SAML enabled |
| `usermanager.server.config.saml.user.email` | SAML assertion attribute mapping to email. | `email` | If SAML enabled |
| `usermanager.server.config.saml.user.image` | SAML assertion attribute mapping to profile image. | `image` | No |
| `usermanager.server.authPrivateKey.secret.name` | Name of the Kubernetes Secret containing the authentication private key (PEM). | `auth-private-key` | Yes |
| `usermanager.server.authPrivateKey.secret.key` | Key in the Secret for the private key file. | `auth-private-key.pem` | Yes |
| `usermanager.server.tls.enabled` | Enable TLS for the User Manager server (required for LDAPS or DB SSL with private CA). | `false` | No |
| `usermanager.server.tls.ca.secretName` | Name of the Secret containing the CA certificate. | &mdash; | If TLS enabled |
| `usermanager.server.tls.ca.key` | Key in the Secret for the CA certificate file. | &mdash; | If TLS enabled |

### Polyspace Access Settings

| Property | Description | Default | Required |
|---|---|---|---|
| `polyspaceAccess.db.passwordString` | Plaintext password for the `prs_data` database role. | &mdash; | If not using passwordSecret |
| `polyspaceAccess.db.passwordSecret.name` | Name of the Kubernetes Secret containing the database password. Preferred over `passwordString`. | &mdash; | If not using passwordString |
| `polyspaceAccess.db.passwordSecret.key` | Key in the Secret that holds the password value. | &mdash; | If using passwordSecret |
| `polyspaceAccess.db.external.enabled` | Use an external PostgreSQL instance instead of the bundled database container. | `false` | No |
| `polyspaceAccess.db.external.host` | Hostname or IP of the external PostgreSQL server. | &mdash; | If external enabled |
| `polyspaceAccess.db.external.port` | Port of the external PostgreSQL server. | &mdash; | If external enabled |
| `polyspaceAccess.db.external.passwordSecret.name` | Name of the Secret containing the external database password. | &mdash; | If external enabled |
| `polyspaceAccess.db.external.passwordSecret.key` | Key in the Secret for the external database password. | &mdash; | If external enabled |
| `polyspaceAccess.webServer.license.secretName` | Name of the Kubernetes Secret containing the MathWorks license file. | `mw-license` | Yes |
| `polyspaceAccess.webServer.license.key` | Key in the Secret for the license file. | `license.lic` | Yes |

### Issue Tracker Settings

| Property | Description | Default | Required |
|---|---|---|---|
| `issuetracker.enabled` | Deploy the Issue Tracker service. | `false` | No |
| `issuetracker.server.provider` | Issue tracker provider. Values: `none`, `jira`, `polarion`, `redmine`. | `none` | If enabled |
| `issuetracker.server.configSecret.name` | Name of a Secret containing the issue tracker configuration JSON. Takes precedence over inline `config` values. | &mdash; | No |
| `issuetracker.server.configSecret.key` | Key in the Secret for the configuration JSON file. | &mdash; | If using configSecret |
| `issuetracker.server.config.url` | Base URL of your issue tracker instance. | &mdash; | If enabled (inline config) |
| `issuetracker.server.config.jiraType` | Jira deployment type. Values: `server`, `cloud`, `dataCenter`. | &mdash; | If provider is jira |
| `issuetracker.server.config.authnMethod` | Authentication method for Jira. Values: `cookie` (server only), `oauth1`, `oauth2` (cloud/dataCenter). | &mdash; | If provider is jira |
| `issuetracker.server.config.authnConfig.consumerKey` | OAuth1 consumer key registered in Jira. | &mdash; | If authnMethod is oauth1 |
| `issuetracker.server.config.authnConfig.callbackBaseURL` | OAuth1 callback URL base. | &mdash; | If authnMethod is oauth1 |
| `issuetracker.server.config.authnConfig.privateKeyPath` | Path to the OAuth1 private key in the container. | &mdash; | If authnMethod is oauth1 |
| `issuetracker.server.config.authnConfig.clientId` | OAuth2 client ID. | &mdash; | If authnMethod is oauth2 |
| `issuetracker.server.config.authnConfig.clientSecret` | OAuth2 client secret. | &mdash; | If authnMethod is oauth2 |
| `issuetracker.server.config.authnConfig.redirectURL` | OAuth2 redirect URL. | &mdash; | If authnMethod is oauth2 |
| `issuetracker.server.config.authnConfig.scopes` | OAuth2 scopes (Jira Cloud only). | `[]` | If oauth2 + cloud |
| `issuetracker.server.config.authnConfig.siteURL` | Jira Cloud site URL for OAuth2. | &mdash; | If oauth2 + cloud |
| `issuetracker.server.config.apiKey` | API key for Polarion or Redmine authentication. | &mdash; | If provider is polarion or redmine |

## Breaking Changes

There are no breaking changes for R2026b. This is the initial release of the Kubernetes installation method.

## Known Issues and Limitations

- **LDAP required with SAML** &mdash; When SAML is configured, you must also configure an LDAP provider for user synchronization.
- **Deployments cannot be scaled** &mdash; Each service deployment is limited to one replica and cannot be scaled horizontally.
- **Database passwords in plaintext** &mdash; The `usermanager.server.config.db.password` property stores the password in plaintext in `values.yaml`. Use `polyspaceAccess.db.passwordSecret` where available.

## License

The license for the software in this repository is available in the [LICENSE.md](LICENSE.md) file.

## Request Enhancements

To suggest additional features or capabilities, see [Request Reference Architectures](https://www.mathworks.com/products/reference-architectures/request-new-reference-architectures.html).

## Technical Support

If you require assistance or additional features, contact [MathWorks Technical Support](https://www.mathworks.com/support/contact_us.html).

---

Copyright 2026 The MathWorks, Inc.
