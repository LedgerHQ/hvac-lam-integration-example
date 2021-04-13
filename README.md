# Integrate HashiCorp Vault with LAM for seed and certificate storage

Integrate HashiCorp Vault with LAM to store seeds and certificates using:

- [An OIDC integration](#oidc-setup)
- [A username and password](#userpass-setup)

## Prerequisites

These intructions are intended to work with a Linux System.

They've been working and tested with docker-compose (version == 1.27.4),
docker (version == 19.03.8) on an Ubuntu system (version == 20.04.2 LTS),
as well as on a MacOS Sierra system.

### Dependencies to install

- The `vault` CLI tool ([installation documentation](https://www.vaultproject.io/docs/install))
- A working [`Python` interpreter](https://www.python.org/downloads/) in your path
- The [`jq` tool](https://stedolan.github.io/jq/)

## Project structure

In the [`hvac/`](./hvac) folder, there is:

- A [`docker-compose.yml`](./hvac/docker-compose.yml) file which is used to bring up the HashiCorp Vault
  and LAM image up together.

- An [`env_files/`](./hvac/env_files/) folder which contains the environment variables needed
  to start LAM and the HashiCorp Vault together. You need to customize
  the following environment variable values to suit your needs:
  - [`oidc.env`](./hvac/env_files/oidc.env): settings of your OIDC app: `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `OIDC_DISCOVERY_URL` are mandatory
    for your OIDC provider to integrate with HashiCorp Vault.
  - [`lam.env`](./hvac/env_files/lam.env): settings for your LAM repository. You should only need to update `WORKSPACE` and `API_GATEWAY_BASE_URL`.
  - [`hvac.env`](./hvac/env_files/hvac.env): settings for the HashiCorp Vault.
- A [`certs/`](./hvac/certs/) folder. This folder must contain the three cryptographic items needed to
  use LAM:
    - [`lam.certificate`](./hvac/certs/lam.certificate)
    - [`lam_public.pem`](./hvac/certs/lam_public.pem)
    - [`lam_private.pem`](./hvac/certs/lam_private.pem)

  In this repo this three files are placeholders,
  you need to replace them with your own
  certificates that have been given to you when you started the on-boarding process.

- A [`setup-oidc.sh`](./hvac/setup-oidc.sh) script to setup HashiCorp Vault to be used by LAM with `oidc` authentication method.
- A [`setup-userpass.sh`](./hvac/setup-userpass.sh) script to setup HashiCorp Vault to be used by LAM with `userpass` authentication method.


## Set up authentication with OIDC

<a name="oidc-setup"/>

### Configure OIDC

The first thing to do is to find your oidc
parameters and to substitute
the `${OIDC_CLIENT_ID}`,
`${OIDC_CLIENT_SECRET}` and `${OIDC_DISCOVERY_URL}`
in [the `oidc.env` file](./hvac/env_files/oidc.env).

Starting from the root of this repository, you can run:

```
cd hvac/
docker-compose up
export $(cat env_files/*.env | xargs) && ./setup-oidc.sh
```

### Test

Make sure the settings for the OIDC app are correct before trying to login. If they are,
you can then run:

```
export $(cat ./env_files/hvac.env | xargs)
vault login -method oidc
```

to authenticate and get your first token.

To verify that everything works fine, you can try to create a user:

```
curl -X POST -H "Content-Type: application/json" -H "X-Ledger-Store-Auth-Token: $(cat ~/.vault-token)" http://localhost:5000/api_users -d '{"name": "test"}'
```

## Set up authentication per user with a username and password

<a name="userpass-setup"/>

### Configure userpass

Starting from the root of this repository, you can run:

```
cd hvac/
docker-compose up
./setup-userpass.sh
```

### Test

Similarly to OIDC, you can run:
```
export $(cat ./env_files/hvac.env | xargs)
vault login -method=userpass username=${HASHICORP_USERPASS_NAME} password=${HASHICORP_USERPASS_PWD}
```
to authenticate and get your first token.

To verify that everything works fine, you can try to create a user:

```
curl -X POST -H "Content-Type: application/json" -H "X-Ledger-Store-Auth-Token: $(cat ~/.vault-token)" http://localhost:5000/api_users -d '{"name": "test"}'
```

You can create more users having access to a different set of API users:

```
vault write auth/userpass/users/new_user_name password=strong_password policies=${HASHICORP_POLICY_NAME}
```


## Handle API user files

HashiCorp Vault is running in dev mode, which means that it has no persistent storage. Obviously this shouldn't be used in production.

During your tests, you may need to restart the container, which would lead to losing the API users you've created so far.

To avoid this, here are two scripts to back up the users' seeds from HashiCorp, and a third one to restore them back. They use the HashiCorp Vault root token to get access to all seeds.

```bash
docker-compose up
# ...
# hashicorp vault is running, and you create some API users
# ...

# export the hvac env vars to be able to use the vault command line
export $(cat ./env_files/hvac.env | xargs)

# backup your seeds on your filesystem (folder name is optional, `users_backup` per default)
./hvac-users.sh backup backup_folder

# restart your env from scratch
docker-compose down && docker-compose up
# ... + run the commands described in the previous sections

# restore your seeds (folder name is optional, `users_backup` per default)
./hvac-users.sh upload backup_folder

# to restore a specific set of seeds or move them to another user
./hvac-users.sh upload backup_folder/alice@ledger.fr/.user_store bob@ledger.fr

# make sure your users are available again
vault login -method oidc
curl -X GET -H "Content-Type: application/json" -H "X-Ledger-Store-Auth-Token: $(cat ~/.vault-token)" http://localhost:5000/api_users
```
