#!/bin/bash
# rbd incremental backup
# Stephen McElroy - 2017
# Usage: ceph_rbd_backup.sh

# Lets define some varibles
    TIME_START=$(date +%Y-%m-%d:%H:%M)
    TODAY=$(date --rfc-3339=date)
    NFS_DIR=/mnt/ceph_backups
    RBD_BCK_DIR=/opt/ceph-backups
    CONFIG_DIR=/opt/ceph-backup/config/
    LASTWEEK=$(date +%Y-%m-%d -d "-7 days")

# Setup our backup folder for todays date and prep our log file
    BACKUP_DIR="$RBD_BCK_DIR/log/"
    LOG_FILE="${BACKUP_DIR}/${TIME_START}-backup.log"
    mkdir -p $BACKUP_DIR
    touch $LOG_FILE

# Formatting for log files
    ERROR_MSG=$(echo "[`tput setaf 1``tput bold`ERROR`tput sgr0`]")
    WARNING_MSG=$(echo "[`tput setaf 3``tput bold`WARNING`tput sgr0`]")
    DEBUG_MSG=$(echo "[`tput setaf 4``tput bold`DEBUG`tput sgr0`]")
    INFO_MSG=$(echo "[`tput setaf 7``tput bold`INFO`tput sgr0`]")
    FATAL_MSG=$(echo "[`tput setaf 1``tput bold`FATAL`tput sgr0`]")
    CRITICAL_MSG=$(echo "[`tput setaf 1``tput bold`CRITICAL`tput sgr0`]")

# Make varibles for snap suffix
    FULL_BACKUP_SUFFIX='.full'
    SNAP_BACKUP_SUFFIX='.snap'
    DIFF_BACKUP_SUFFIX='.difffrom'
    COMPRESSED_BACKUP_SUFFIX='.tar.gz'

# Basic Loging Function
function log () {
            echo "$1" >> $LOG_FILE
}

function archive() {
    tar cvf - $(find $IMAGE_DIR/* -mtime -6 -type f \( ! -iname "*$COMPRESSED_BACKUP_SUFFIX" \)) | \
          gzip -9c > ${IMAGE_DIR}/${LOCAL_IMAGE}_${LASTWEEK}_to_${TODAY}${COMPRESSED_BACKUP_SUFFIX}

    if [[ -f ${IMAGE_DIR}/${LOCAL_IMAGE}_${LASTWEEK}_to_${TODAY}${COMPRESSED_BACKUP_SUFFIX} ]]; then
            rm -f $(find $IMAGE_DIR/* -mtime -6 -type f \( ! -iname "*${COMPRESSED_BACKUP_SUFFIX}" \))
            rbd snap purge $POOL/$LOCAL_IMAGE
    else
            log "file not created"
    fi
}


# Its go time
log "$INFO_MSG Ceph Backup Started $TIME_START"

for CONFIG in $(find $CONFIG_DIR -name *.conf); do

POOL=$(awk '/^\[PoolInfo\]/{f=1} f==1&&/^poolname/{print $3;exit}' "${CONFIG}")
echo $POOL
if [[ -z "$POOL" ]]; then
     log "$ERROR_MSG[$POOL] Config file jacked up - Name left blank"
     continue
fi

FULL_DAY=$(awk '/^\[PoolInfo\]/{f=1} f==1&&/^fullday/{print $3;exit}' "${CONFIG}")

log "$INFO_MSG Backing up images in $POOL"

 # Take all the Image names from a pool and dump it into a varible
 IMAGES=`rbd ls $POOL`

for LOCAL_IMAGE in $IMAGES; do

IMAGE_DIR="$NFS_DIR/$POOL/$LOCAL_IMAGE"

if [[ ${FULL_DAY} == $(date +%u) ]]; then
    archive
fi

log "$INFO_MSG Backing up image - $LOCAL_IMAGE"
  # initialize local varibles

  if [[ ! -e "$IMAGE_DIR" ]]; then
        log "$INFO_MSG No initial image dir, creating $IMAGE_DIR"
        mkdir -p "$IMAGE_DIR"
  fi

    # check if there is snapshot to backup
    LATEST_SNAP=`rbd snap ls $POOL/$LOCAL_IMAGE |grep -v "SNAPID" |sort -r | head -n 1 |awk '{print $2}'`
    if [[ -z "$LATEST_SNAP" ]]; then

        log "$INFO_MSG No initial base image, exporting it to disk"
        log "$INFO_MSG No initial snap, creating it"
        log "$INFO_MSG Exporting initial snap file to disk"

        # full export the image, then create a snap of it, save the snap
        rbd export $POOL/$LOCAL_IMAGE $IMAGE_DIR/${LOCAL_IMAGE}${TODAY}${FULL_BACKUP_SUFFIX}  >/dev/null 2>&1
        rbd snap create $POOL/$LOCAL_IMAGE@${LOCAL_IMAGE}${TODAY}${SNAP_BACKUP_SUFFIX} >/dev/null 2>&1

        # export the first snapshot
        rbd export-diff $POOL/$LOCAL_IMAGE@${LOCAL_IMAGE}${TODAY}${SNAP_BACKUP_SUFFIX} \
                        $IMAGE_DIR/${LOCAL_IMAGE}${TODAY}${DIFF_BACKUP_SUFFIX}_${LOCAL_IMAGE}${TODAY}${SNAP_BACKUP_SUFFIX}  >/dev/null 2>&1
        continue
    fi



        rbd snap create $POOL/$LOCAL_IMAGE@${LOCAL_IMAGE}${TODAY}${SNAP_BACKUP_SUFFIX}
        LATEST_SNAP=`rbd snap ls $POOL/$LOCAL_IMAGE |grep -v "SNAPID" |sort -r | head -n 1 |awk '{print $2}'`
        
        # export the diff of current and last snapshot
        LAST_SNAP=`ls $IMAGE_DIR -1 -rt |tail -n 1|awk -F_ '{print $2}'`

        if [[ $LATEST_SNAP == $LAST_SNAP ]]; then
             log "$WARNING_MSG Last snap the same, backup already done, skipping"
             continue
        fi

        log "$INFO_MSG Creating todays snap - ${LOCAL_IMAGE}${TODAY}${SNAP_BACKUP_SUFFIX}"
        log "$INFO_MSG Creating diff from old snap - ${LAST_SNAP}"
        log "$INFO_MSG Exported diff to ${LAST_SNAP}${DIFF_BACKUP_SUFFIX}_${LATEST_SNAP}"

        #rbd snap create $POOL/$LOCAL_IMAGE@${LOCAL_IMAGE}${TODAY}${SNAP_BACKUP_SUFFIX}
        rbd export-diff --from-snap ${LAST_SNAP} ${POOL}/${LOCAL_IMAGE}@${LATEST_SNAP} \
                                    ${IMAGE_DIR}/${LAST_SNAP}${DIFF_BACKUP_SUFFIX}_${LATEST_SNAP}
        rbd snap rm $POOL/$LOCAL_IMAGE@${LAST_SNAP}

        log "$INFO_MSG Deleting old snap - ${LAST_SNAP}"

  done
done
