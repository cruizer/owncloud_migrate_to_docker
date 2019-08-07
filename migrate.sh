#!/bin/bash
# Migrate an existing Owncloud server to the Dockerized deployment
started_at=$(date +"%Y%m%d-%H%M%S")
db_backupfile=owncloud-dbbackup_${started_at}.bak
stack_name=owncloudd
echo "Owncloud migration script invoked at $started_at"
# UTILITY FUNCTIONS
# Returns the container ID for the given service name
get_service_containerid(){
    docker ps -f "name=${stack_name}_$1" --format='{{.ID}}'
}
# Reads the Owncloud config item with the name passed as its argument.
oc_conf_read(){
    php -r "include \"${oc_currdir}/config/config.php\";print(\$CONFIG[\"$1\"]);"
}
stage_proceed_confirmation(){
    while true;do
	echo -n "Next step: $1. \
	     Do you want to proceed to the next stage? (Y/N) "
	read proceed
	proceed=$(echo $proceed | tr '[:upper:]' '[:lower:]')
	if [ $proceed == 'y' ];then
	    break
	elif [ $proceed == 'n' ];then
	    echo "Exiting on user request."
	    exit 1
	else
	    echo "Invalid choice: $proceed"
	fi	 
    done
}
# STEPS
cat <<EOF
***This script migrates your current Owncloud installation to a new deployment using the
official Owncloud Docker image.***

Before proceeding, please make sure, you have backed up the following to a safe location:

- The Owncloud *data* and *config* directories.
- The Owncloud database.

You *MUST HAVE* your Owncloud file data directory at /mnt/data/files for this to work! Please
refer to the README document for details on how you can move your file data if it is elsewhere (which is likely).
EOF
# Read current owncloud directory from user
read -p "Please provide the absolute path of your Owncloud deployment:" \
     oc_currdir # for me, it is /var/www/owncloud
if [ -f "$oc_currdir/config/config.php" ];then
    echo "The original config file is present, the path is verified."
else
    echo "The original config file is not found. Exiting!"
    exit 1
fi
oc_backup_path=/root/oc-backup
mkdir -p $oc_backup_path
echo "Checking if the current database type is one of MySQL or MariaDB."
oc_dbtype=$(oc_conf_read dbtype)
if [ $oc_dbtype == 'mysql' ] || [ $oc_dbtype == 'mariadb' ];then
    echo "Database type check OK."
else
    echo "Database type check FAILED: $oc_dbtype is not \
    	 compatible with the OC default MariaDB. Manual migration required."
    exit 1
fi
stage_proceed_confirmation "database backup"
echo "Creating the database backup"
mysqldump --single-transaction \
	  -h $(oc_conf_read dbhost) \
	  -u $(oc_conf_read dbuser) \
	  -p$(oc_conf_read dbpassword) \
	  $(oc_conf_read dbname) > ${oc_backup_path}/${db_backupfile}
stage_proceed_confirmation "download docker-compose.yml"
echo "Fetching docker-compose.yml for the Owncloud stack."
wget -O docker-compose.yml https://raw.githubusercontent.com/owncloud-docker/server/master/docker-compose.yml
echo "Customizing the stack config to match the current server."
# Collecting the port config from the user
while true;do
    echo -n "Enter the port you want to use for the Owncloud service: "
    read newport
    netstat -nap | grep -q ':'"$newport"'.*LISTEN'
    if [ $? -eq 1 ];then
	echo "Port $newport is not used. OK."
	break
    else
	echo "Port $newport is already used. Please provide a different one."
    fi
done
stage_proceed_confirmation "customizing the docker-compose.yml file"
sed -i.orig \
    -e "s/^version:.*/version: \'3\'/" \
    -e 's/${OWNCLOUD_VERSION}/'"$(oc_conf_read version | sed -E 's/([0-9]+\.[0-9]+).*/\1/')"'/' \
    -e 's/${HTTP_PORT}/'"${newport}"'/' \
    -e 's/${OWNCLOUD_DOMAIN}/'"$(hostname -f)"'/' \
    -e 's/${ADMIN_USERNAME}/admin/' \
    -e 's/${ADMIN_PASSWORD}/owncloudadmin/' \
    docker-compose.yml
stage_proceed_confirmation "stack deployment on Docker"
echo "Deploying the stack to Docker"
docker stack deploy -c docker-compose.yml $stack_name
echo "Waiting 5 minutes for the containers to stabilize..."
sleep 300
stage_proceed_confirmation "turning on maintenance mode"
echo "Turning on Owncloud maintenance mode"
docker exec $(get_service_containerid owncloud) \
       occ maintenance:mode --on
stage_proceed_confirmation "copying the db backup to the volume"
echo "Copying backup file to the db container volume"
docker run \
       --rm \
       --mount type=bind,src=${oc_backup_path},dst=/mnt \
       --mount type=volume,src=${stack_name}_backup,dst=/backup \
       ubuntu \
       cp /mnt/${db_backupfile} /backup
stage_proceed_confirmation "restoring the OC database"
echo "Restoring the Owncloud database"
docker exec $(get_service_containerid db) \
       /bin/bash \
       -c "mysql -h localhost \
       -u owncloud \
       -powncloud \
       owncloud < /var/lib/backup/${db_backupfile}"
stage_proceed_confirmation "copying the OC file data"
echo "Copying the file data to the container volume."
docker run \
       --rm \
       --mount type=bind,src=${oc_currdir}/data,dst=/mnt \
       --mount type=volume,src=${stack_name}_files,dst=/filesvol \
       ubuntu \
       /bin/bash -c \
       "cp /filesvol/files/.htaccess /tmp; \
       cp -rp /mnt/. /filesvol/files; \
       cp /tmp/.htaccess /filesvol/files"
stage_proceed_confirmation "updating config file secrets"
echo "Updating the configuration secrets"
docker exec $(get_service_containerid owncloud) \
       sed -i.orig \
       -e "s#'secret'.*#'secret' => '$(oc_conf_read secret)',#" \
       -e "s#'secret'.*#'passwordsalt' => '$(oc_conf_read passwordsalt)',#" \
       /var/www/owncloud/config/config.php
stage_proceed_confirmation "run occ upgrade manually"
cat <<EOF
In the next step, the script will take you to the shell of the Owncloud container.

Please run the following commands manually, to finalize the migration:

1) First, update the data fingerprint:

    # occ maintenance:data-fingerprint

2) Then, you need to execute the upgrade script. If it complains about upgrading
   some of the apps downloaded from the OC Marketplace, just disable them as
   instructed and run the upgrade command again. Once you are done with
   the migration, you can log on with your "old" admin user and install the apps from
   the marketplace.

    # occ upgrade

3) If everything went as planned, turn off maintenance mode:

    # occ maintenance:mode --off

Once you are done, verify, that you can access the Owncloud web interface
and that your migrated data, users, etc. are migrated.

If all is good, you can leave the container shell with:

    # exit

If something went wrong and you want to run the script again, don't forget to delete the
Owncloud stack and volumes first!

EOF
echo "Loading the Owncloud container's shell:"
docker exec -ti $(get_service_containerid owncloud) \
       /bin/bash
