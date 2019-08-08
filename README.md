# Migration script to migrate my Owncloud deployment to the official Docker image

* This is work in progress, use it at your own risk!
* It is very likely you will have to customize some parts to make it working for you.

## Prerequisites

- This migration script will only work if you are using *MySQL* or *MariaDb* as your Owncloud database backend.
- The official Owncloud Docker image expects a volume mounted at `/mnt/data` inside the container, that contains your Owncloud file data in `/mnt/data/files`*. Hence, you need to migrate your file data from its current location to `/mnt/data` first, before you can start the migration. For instance, in my case, I have migrated the contents of `/var/www/owncloud/data` into `/mnt/data/files`. You should follow the [official documentation](https://doc.owncloud.com/server/admin_manual/maintenance/manually-moving-data-folders.html) for moving the data.
  *Actually, there are two environment variables `OWNCLOUD_VOLUME_ROOT` and `OWNCLOUD_VOLUME_FILES` existing inside the [Owncloud container](https://github.com/owncloud-docker/base/blob/master/rootfs/etc/entrypoint.d/50-folders.sh), where the Owncloud root and file data paths are read from. However, most existing Owncloud deployments are running with `/var/www/owncloud` being the root for the deployment. This is a problem, as mounting the data volume to `/var/www/owncloud` inside the container would mask the files already existing there.
- Create a backup of the current Owncloud `data` and `config` directories.
- Create a backup of the Owncloud database.
- Initialize the target Docker Swarm.

## This is what the script does on a high level

01. You need to provide the absolute path to the root directory of your current Owncloud deployment. The script needs this in order to extract information from the configuration file `config.php`.
02. The script creates a backup of your Owncloud database.
03. The script downloads the example `docker-compose.yml` file from the official *owncloud-docker/server* project.
04. You need to provide a port number, that should be used for the Owncloud service.
05. The script updates the `docker-compose.yml` file with the information collected from the existing `config.php` file and your input:
  - The `docker-compose.yml` file's version, to make deployment to Docker Swarm possible.
  - The Owncloud version (it will match the current version, you can upgrade later after the migration is done).
  - The HTTP port.
  - The FQDN used to access the Owncloud service.
  - The default admin credentials (these will be overridden later, when your current Owncloud database is restored).
06. The script deploys the stack on Docker Swarm.
07. Once the Owncloud service has stabilized, the script turns on *maintenance mode*.
08. The script copies the database backup to the MariaDB container.
09. The script restores the database backup in the MariaDB container.
10. The script copies the Owncloud file data onto the Owncloud container volume.
11. The script updates the config file secrets.
12. The script drops you into the Owncloud container shell, where you will complete the last 3 steps of the migration manually:
  - Update the file data fingerprint.
  - Run the Owncloud upgrade tool.
  - Turn maintenance mode off.