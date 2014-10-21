#!/bin/bash

CLIENT_INDEX=1
ALT_CLIENT_INDEX=2
BLOCK_START='# Time:*'
CLIENT_LINE='# Client:*'
REPORT_END='# #######*'
declare -a data_block=()
declare -i end_of_report=0
declare -i block_size=0
declare -i block_index=0

add_to_tracked () {
    client_id="$1"
    for index in `seq 0 $block_index`; do
        echo "${data_block[$index]}" >> tracked/$client_id
    done
}

add_to_candidate () {
    client_id="$1"
    for index in `seq 0 $block_index`; do
        echo "${data_block[$index]}" >> candidates/$client_id
    done
}

process_block () {
    if [ "$block_index" -eq 0 ]; then
        return
    fi
    client_element=${data_block[$CLIENT_INDEX]}
    if [[ "$client_element" != $CLIENT_LINE ]]; then
        client_element=${data_block[$ALT_CLIENT_INDEX]}
    fi
    client_id=${client_element:10}
    if [ -f "tracked/$client_id" ]; then
        add_to_tracked $client_id
    else
        add_to_candidate $client_id
    fi
}

# MAIN
block_index=0
while read line; do
    if [ $end_of_report -eq 1 ]; then
        continue
    fi
    if [[ "$line" == $REPORT_END ]]; then
        process_block
        end_of_report=1
    elif [[ "$line" == $BLOCK_START ]]; then
        process_block
        block_index=0
        data_block=( "$line" )
    else
        block_index=$block_index+1
        data_block[$block_index]="$line"
    fi
done < /dev/stdin
