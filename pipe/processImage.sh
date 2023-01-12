#!/bin/bash
#Gets called once per image. Use this script to run any programs you'd like on your image prior to import

zarr(){
    /docker/log.sh INFO "converting to zarr"
    /docker/bin/bioformats2raw -p --max_workers=$threads "$currentImg" "/out/$2/$dataset/${filename%.*}/" $BF2RAW_ARGS
    /docker/log.sh INFO "converted to zarr"
}

ometiff(){
    /docker/log.sh INFO "converting to ome.tiff"
    /docker/bin/bioformats2raw -p --max_workers=$threads "$currentImg" "$workdir/zarr" $BF2RAW_ARGS 
    mkdir -p "/out/$2/$dataset/" && /docker/log.sh INFO "converted to zarr"
    /docker/bin/raw2ometiff -p --max_workers=$threads "$workdir/zarr" "/out/$2/$dataset/${filename%.*}.ome.tiff" $RAW2TIFF_ARGS
    /docker/log.sh INFO "converted to ome.tiff"
}

main(){    
    #gather title info
    local filename=${1##*/}
    local parentPath=${1%/*}
    # echo $(echo $parentPath | sed "s/\/in\/$2\///g")
    local datasetPath=$(echo $parentPath | sed "s/\/in\/$2\///g")
    local dataset=${datasetPath%%/*}
    local threads=${BASE_THREADS:-1}

    [[ -z $dataset ]] && dataset=orphaned

    # if priority import rename and add threads
    [[ $filename =~ "PRIORITY_" ]] && 
        filename=${filename#PRIORITY_} &&
        threads=${PRIORITY_THREADS:-2} 

    local workdir=/tmp/PROCESSING/$filename.d
    local currentImg=$workdir/$filename

    echo $1
    echo $filename $dataset $2

    #mv to tmp directory (to avoid multiple calls on same file) 
    [[ -d $workdir ]] && /docker/log.sh ERROR "Work directory for $filename is already occupied!" && exit 1
    /docker/log.sh INFO "PROCESSING $filename"
    mkdir -p $workdir
    mv $1 $workdir/$filename
    
    # stdout for scraper
    local stdout=$workdir/out
    mkfifo $stdout
    
    #convert to zarr
    if [[ $CONVERT_TO_ZARR ]]; then
        cat $stdout > /dev/null &
        /docker/log.sh INFO "converting to zarr"
        /docker/bin/bioformats2raw -p --max_workers=$threads "$currentImg" "/out/$2/$dataset/${filename%.*}/" $BF2RAW_ARGS >$stdout 2>&1 
        /docker/log.sh INFO "converted to zarr"
    fi 

    #convert to ome.tiff
    if [[ $CONVERT_TO_TIFF ]]; then 
        /docker/log.sh INFO "converting to ome.tiff"
        mkdir -p "/out/$2/$dataset" 

        cat $stdout > /dev/null &
        /docker/bin/bioformats2raw -p --max_workers=$threads "$currentImg" "$workdir/zarr" $BF2RAW_ARGS >$stdout 2>&1  
        /docker/log.sh INFO "converted to zarr"
        cat $stdout > /dev/null &
        /docker/bin/raw2ometiff -p --max_workers=$threads "$workdir/zarr" "/out/$2/$dataset/${filename%.*}.ome.tiff" $RAW2TIFF_ARGS >$stdout 2>&1 
        /docker/log.sh INFO "converted to ome.tiff" 
    fi

    #zip and archive (medusa?siren? wherever rsync goes now.)
    # [[ $ARCHIVE_ORIGINAL ]] && /docker/archiveWSI.sh $currentImg ${2%/} $parentPath

    #these files are huge, cannot afford to keep them kicking around
    /docker/log.sh INFO "cleaning workdir"
    rm -rf $workdir
}

[[ -z $1 ]] && /docker/log.sh ERROR "No file provided" && exit 1
main $@