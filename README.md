# Ceph RBD backup script

 *Had to take this down till I resolve weather or not I can post this, legal mumbo jumbo stuff. Ill leave my snippits up in the readme though*
 
 Releasing the v0.1.1 of **ceph\_rbd\_bck.sh**. I wrote this to provide an opensource solution to backing Ceph pools. I needed something to not only backup individual images in specified pools, but to also be able to set retention dates, and implement a synthetic full backup schedule. This is an extremely easy script intended help other people backup thier systems, or develop a more robust backup solution.

## Getting started

 First it should be noted that this script was created and tested on a machine running Centos 7.2. It may as is on other distros, or need minor tweaking to get working right. The machine you are running this on will need two basic things
   
   * Admin access to your current Ceph Cluster
   * A place to your backups (I recommend **NOT** on the cluster you are currently backing up)
 
This can be done from your admin node in Ceph using ceph-deploy

```bash
$ yum install ceph-deploy
$ ceph-deploy install [BACKUP HOST]
$ ceph-deploy admin [BACKUP HOST]
```

To get started please create working directory for us to put our scripts and config files in. By default the config directory will be in **/opt/ceph_backups/config**

```bash
mkdir -p /opt/ceph_backups/config
```

## Making config files

These config files are extremely simple and are for each individual pool. This will allow you to fine tune any pool to your liking and setup a staggered backup schedule. These should be placed in **/opt/ceph_backups/config** and have the **'.conf'** file extension. Each pool will require its own separate config file.

```bash
# YMCA_pool.conf
# 
# poolname - Name of pool to be backed up in Ceph
# fullday - day that the script should archive the last 7 days worth of backups
#           and create a new full/initial snapshot export. Note that this is numerical and 
#           monday starts the week, monday=1 ... sunday= 7
# retention - how long backups should be kept before the archive is pruned off 

[PoolInfo]
poolname = YMCA_pool
fullday = 5
retention = 28
```

## Specific Script Notes

#### Logging Function

This is easy enough, by call ing **log** with a text string this will log it to a file. Note that cat'ing the file will produce color coded error tags, while opening it in vi will look off due to tput.

```bash
log "$ERROR_MSG Goodbye world"
cat file.log
...
[ERROR] Goodbye world
...
```
```bash
# Formatting for log files
    ERROR_MSG=$(echo "[`tput setaf 1``tput bold`ERROR`tput sgr0`]")
    WARNING_MSG=$(echo "[`tput setaf 3``tput bold`WARNING`tput sgr0`]")
    DEBUG_MSG=$(echo "[`tput setaf 4``tput bold`DEBUG`tput sgr0`]")
    INFO_MSG=$(echo "[`tput setaf 7``tput bold`INFO`tput sgr0`]")
    FATAL_MSG=$(echo "[`tput setaf 1``tput bold`FATAL`tput sgr0`]")
    CRITICAL_MSG=$(echo "[`tput setaf 1``tput bold`CRITICAL`tput sgr0`]")
```

```bash
# Basic Loging Function
function log () {
            echo "$1" >> $LOG_FILE
}
```
#### Archiving Function

This finds everything less than 7 days old (*mtime -6*), excluding tar.gz files, in the backup folder for the specific image.
If the archive exsits, remove all the old files and purge all snapshots. This will trigger a new full and initial snapshot to be created.

```bash
function archive() {
    tar cvf - $(find $IMAGE_DIR/* -mtime -6 -type f \( ! -iname "*$COMPRESSED_BACKUP_SUFFIX" \)) | \
          gzip -9c > ${IMAGE_DIR}/${LOCAL_IMAGE}_${LASTWEEK}_to_${TODAY}${COMPRESSED_BACKUP_SUFFIX}

    if [[ -f ${IMAGE_DIR}/${LOCAL_IMAGE}_${LASTWEEK}_to_${TODAY}${COMPRESSED_BACKUP_SUFFIX} ]]; then
            rm -f $(find $IMAGE_DIR/* -mtime -6 -type f \( ! -iname "*${COMPRESSED_BACKUP_SUFFIX}" \))
            rbd snap purge $POOL/$LOCAL_IMAGE
    else
            log "$ERROR_MSG File not created"
    fi
}
```

#### Retention Function

This finds everything older than a given varible "**[retention_time]**" (*mtime +[retention_time]*) in the backup folder for the specific image and deletes it. This is very simple and  is just here to delete old archive files. **Note: I will add in eventually a safeguard to ensure that only compressed archives get the axe.**

```bash
# Usage: retention [bck_directory] [retention_time]
function retention() {
      find $1/* -mtime +$2 | xargs rm
}
```
