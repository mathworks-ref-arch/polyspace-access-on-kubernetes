# Deploy Polyspace Access Web Server

## Things to note

- `polyspace-access-[RELEASE].zip` contains application docker images (`.tar` files).

- Helm charts for a given release will be shared by MathWorks.

## Prerequisites

1. Kubernetes cluster & namespace must be available for deploying the product.

2. Images provided in the distribution must be available to the cluster.

3. Ingress controller to access application URLs.

## Pre-installation steps

1. Unzip `polyspace-access-[RELEASE].zip`.

2. Retag and upload docker images on to the Image Registry. Refer Kubernetes platform documentation for more details.
   > Alternatively, copy `resources/load-images.sh` into distribution directory and run script to download, retag, and push the images to the image registry.

3. Generate and make usermanager private key available to the application.
   - Generate [usermanager private key](https://www.mathworks.com/help/polyspace_access/install/configure-the-user-manager.html)
   - Create `Secret` using `resources/secrets.yaml`
     ```bash
     kubectl apply -f resources/secrets.yaml -n [NAMESPACE]
     ```

4. Setup license manager if not already done so. See `resources/FlexLM installation and configuration on Linux for Polyspace products.pdf`

5. Make license available to the application.
   - Create `Secret` using `resources/secrets.yaml`
     ```bash
     kubectl apply -f resources/secrets.yaml -n [NAMESPACE]
     ```

6. Customize `values.yaml` or provide override file for the deployment.
   > Choose `values-external-db.yaml` to configure Polyspace&reg; Access&trade; for external (bring-your-own) database.

7. Generate Persistent Volume Claims for production environment (See `.Values.volumes`). For dev environment, providing `.Values.global.volume.storageClassName` will generate the required PVCs.

## Deploy

```shell
# cd to chart directory
helm upgrade --install [RELEASE_NAME] . --namespace=[NAMESPACE] -f [OVERRIDE_FILE_IF_ANY]
```

## Application routes

> HOST:PORT must be provided by the Ingress Controller.

### Polyspace Access Login

http://HOST:PORT/authn/signin
> Credentials depends on how `usermanager` application has been configured.

### User manager dashboard

http://HOST:PORT/um/ui/dashboard
