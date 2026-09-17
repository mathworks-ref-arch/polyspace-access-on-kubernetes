## Chart.version: 0.6.0
### Release: R2026a

- Application versions
    - usermanager:2.45.0
    - issuetracker:3.10.0
    - polyspace-access:26.1.0

- Remove Polyspace&reg; Access&trade; Download service

- Add support for external (usermanager & polyspace-access) databases. Installation can now opt to bring their own pre-configured databases.

- Add flag for PVC creation `.Values.global.volume.create`

- Add ingress url configuration `.Values.global.ingress.url`

- Add support for Polarian issuetracker

## Chart.version: 0.5.0
### Release: R2025a, R2025b

- Application versions
    - usermanager:2.39.2
    - issuetracker:2.41.3
    - polyspace-access:25.1.2

- Introduce SSO support
    - Add new image and respective "usermanager-authnz" service
    - LDAP configuration is still needed

### Known issues

**Issue:** Deployment object names have been reduced. Upgrading from R2024b (or before) may cause old stale deployments to interfere with the current deployment. As a result users may not be able to authenticate into the application.

**Fix:** Use `helm upgrade --install --force` to force delete old deployments and reinstall the chart. Ensure previous deployments are not listed anymore. This will not affect data persisted. 

## Chart.version: 0.4.0
### Release: R2024b

- Application versions
    - usermanager:2.32.3
    - issuetracker:2.41.0
    - polyspace-access:1.9.0-SNAPSHOT

- Drop chart name from Deployment names i.e., from `{{ .Release.Name }}-{{ .Chart.Name }}-` to `{{ .Release.Name }}-`. Example, from `polyspace-release-polyspace-access-polyspace-access-db` to `polyspace-release-polyspace-access-db`.

- Make installation of issuetracker optional via `.Values.issuetracker.enabled`. This will be breaking change if the updated `values.yaml` is not used.

- Add note to create PVCs in production environment.

## Chart.version: 0.3.0
### Release: R2024a

- Add `polyspace-access-download` service and related values

- Update liveness probe endpoints

## Chart.version: 0.2.0
### Release: R2024a

- Update microservices to R2024a
    - usermanager:2.32.1
    - issuetracker:2.38.0

## Chart.version: 0.1.0
### Release: R2023b

- Add injectable `resources` to all containers

- Add injectable `resources` to Persistent Volume Claims

## Chart.version: 0.0.0
### Release: R2023b

- Add option to inject ingress controller annotations
    - Rename `.Values.global.ingressController` to `.Values.global.ingress`
    - Rename `.Values.global.ingressController.name` to `.Values.global.ingress.controllerName`
    - Add `.Values.global.ingress.annotations`
    
- Add tls option `.Values.global.tls`

- Rename `.Values.global.images` to `.Values.global.image`

- Add `.Values.global.image.pullSecrets`

- Remove volume type selection `.Values.global.volume.type`

- Add missing usermanager config
    - `.Values.usermanager.server.config.db.url`
    - `.Values.usermanager.server.config.providers[0].properties.credentials.bindDN`
    - `.Values.usermanager.server.config.providers[0].properties.credentials.bindPassword`
    - `.Values.usermanager.server.config.providers[0].properties.searchOptions.user.schema.member`

- Replace configmap to secret
    - `.Values.usermanager.server.authPrivateKey.configMap` to `.Values.usermanager.server.authPrivateKey.secret`
    - `.Values.polyspaceAccess.webSserver.license.configMap` to `.Values.polyspaceAccess.webSserver.license.secretName` & `Values.polyspaceAccess.webSserver.license.key`

- Remove file support for usermanager authentication private key `.Values.usermanager.server.authPrivateKey.fileSubPath`

- Remove file support for polyspace access license `.Values.polyspaceAccess.webServer.license.fileSubPath`

- Update image tag values from `R2023a` to `R2023b`
    - `.Values.images.usermanager` from `2.28.5` to `2.32.0`
    - `.Values.images.issuetracker` from `2.28.1` to `2.35.0`

- Add `.Values.usermanager.server.tls`

- Inject polyspace-db password via string or secret
    - Rename `.Values.polyspaceAccess.db.password` to `.Values.polyspaceAccess.db.passwordString`
    - Add `.Values.polyspaceAccess.db.passwordSecret` option