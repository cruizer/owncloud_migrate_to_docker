# Migration script to migrate my Owncloud deployment to the official Docker image

- This script was a quick and dirty fix for my Owncloud migration needs. It should work for most standard single server Community Edition deployments, but your mileage may vary. No guarantee is provided.
- If you have an Enterprise or CE system that has custom elements in its deployment or configuration, it is very likely you will have to customize some parts of this to make it work for you.
- This script was used and tested using the *root* user. If you are using a different user to manage your Docker Swarm, you migth need to modify the script in some places. Alternatively, you should also be able to get away with using `sudo` instead.
- For minimum risk, the script copies the Owncloud data to the Docker volume and leaves the original location intact. This means however, that you need to have enough disk space to have two copies of your data on the system. If you just want to use the existing data on your system, it should be possible using a bind mount, but then you need to adjust the `docker-compose.yml` configuration and remove the step for copying the files data.

## Prerequisites

- This migration script will only work if you are using *MySQL* or *MariaDb* as your Owncloud database backend.
- The official Owncloud Docker image expects a volume mounted at `/mnt/data` inside the container. Owncloud files data should be located in `/mnt/data/files`\*. Hence, you need to migrate your files data from its current location to `/mnt/data`, **before** you can start the migration. For instance, I have migrated the contents of `/var/www/owncloud/data` into `/mnt/data/files`. You should follow the [official documentation](https://doc.owncloud.com/server/admin_manual/maintenance/manually-moving-data-folders.html) for moving the data.
- [Create a backup](https://doc.owncloud.com/server/10.2/admin_manual/maintenance/backup.html#backing-up-the-config-and-data-directories) of the current Owncloud `data` and `config` directories.
- [Create a backup](https://doc.owncloud.com/server/10.2/admin_manual/maintenance/backup.html#backup-database) of the Owncloud database.
- Initialize the target [Docker Swarm](https://docs.docker.com/get-started/part4/).

\* Actually, there are two environment variables `OWNCLOUD_VOLUME_ROOT` and `OWNCLOUD_VOLUME_FILES` existing inside the [Owncloud container](https://github.com/owncloud-docker/base/blob/master/rootfs/etc/entrypoint.d/50-folders.sh), where the Owncloud root and file data paths are read from. However, most existing Owncloud deployments are running with `/var/www/owncloud` being the root for the deployment. This is a problem, as mounting the data volume to `/var/www/owncloud` inside the container would mask the files already existing there.

## Executing the migration

To execute the script, I recommend you to create a working directory, where you download `migrate.sh`, then run it. For example:

```bash
# Create the working directory (example)
mkdir /root/docker-owncloud/
# Change to the working directory
cd /root/docker-owncloud/
# Download the migration script
wget -O migrate.sh https://raw.githubusercontent.com/cruizer/owncloud_migrate_to_docker/master/migrate.sh
# Execute
./migrate.sh
```

Both `docker-compose.yml` and `.env` will be saved in this directory.

### Migration steps

01. You need to provide the absolute path to the root directory of your current Owncloud deployment. The script needs this in order to extract information from the configuration file `config.php`.
02. The script checks if your current database backend for Owncloud is one of *MariaDB* or *MySQL*.
03. The script checks if your Owncloud files data is found at `/mnt/data/files` or not.
04. The script checks if your Docker Swarm is initialized.
05. You need to pick one domain name for the Owncloud service from your current configuration. (The official image only supports one domain name.)
06. You need to provide a port number, that should be used for the Owncloud service.
07. You can change the default stack name *owncloudd*.
08. The script downloads the `docker-compose.yml` file from this project.
09. The script exports the environment variables used to fill in the placeholders in `docker-compose.yml`.
10. The script deploys the stack on *Docker Swarm*.
11. Once the Owncloud service has stabilized, the script turns on *maintenance mode*.
12. The script copies the database backup to the MariaDB container.
13. The script restores the database backup in the MariaDB container.
14. The script copies the Owncloud file data onto the Owncloud container volume.
15. The script updates the config file secrets.
16. The script drops you into the Owncloud container shell, where you will complete the last 3 steps of the migration manually:
    - Update the file data fingerprint.
    - Run the Owncloud upgrade tool.
    - Turn maintenance mode off.

## Redeploying the stack

In case you want to redeploy the stack for some reason, you can do:

```bash
# Enable maintenance mode
docker exec <stackname>_owncloud<tab> occ maintenance:mode --on
# Remove the stack
docker stack rm <stackname>
# Navigate to the stack working directory (example)
cd /root/docker-owncloud/
# Source the environment file
. .env
# Deploy the stack
docker stack deploy -c docker-compose.yml <stackname>
# Wait for the container to stabilize for 5 minutes, then
# turn off maintenance mode
docker exec <stackname>_owncloud<tab> occ maintenance:mode --off
```
**NOTE**: The container names are built up from the *stack name* and the *service name*, plus a randomly generated identifier is appended to the name. Hence you need TAB complection to help you with the full name as indicated with `<tab>`.

Make sure, to use the same *stack name*, so that the original database and owncloud data volumes are remounted.

## Upgrades

Since I am using *Docker Swarm*, the upgrade procedure contains similar steps as shown in the [official documentation](https://doc.owncloud.com/server/admin_manual/installation/docker/#upgrading-owncloud-on-docker), but the commands are slightly different:

```bash
# Enable maintenance mode
docker exec <stackname>_owncloud<tab> occ maintenance:mode --on
# Backup the database
docker exec <stackname>_db<tab> backup
# Remove the stack
docker stack rm <stackname>
# Navigate to the stack working directory (example)
cd /root/docker-owncloud/
# Update the .env file with the new version
sed -i 's/^export OWNCLOUD_VERSION=.*$/export OWNCLOUD_VERSION=<newVersion>/' .env
# Source the environment file
. .env
# Deploy the stack
docker stack deploy -c docker-compose.yml <stackname>
# After the stack is deployed the occ upgrade is automatically executed
# If you see the container being in a rolling restart, you can check the status with:
docker logs <stackname>_owncloud<tab> --follow --timestamps
# Otherwise wait for 5 minutes and if the container is stable, disable maintenance mode
docker exec <stackname>_owncloud<tab> occ maintenance:mode --off
```

**NOTE**: The container names are built up from the *stack name* and the *service name*, plus a randonmly generated identifier is appended to the name. Hence you need TAB complection to help you with the full name as indicated with `<tab>`.
