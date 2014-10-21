#!/bin/bash

. ./tc.cnf
declare -A transactions
declare -i tcplog_count
declare -i tcplog_index
declare -i trans_seconds

cleanup () {
    if [ -d "archived" ] ; then
        rm -f archived/*
    else
        mkdir archived
    fi
    if [ -d "candidates" ] ; then
        rm -f candidates/*
    else
        mkdir candidates
    fi
    if [ -d "tracked" ] ; then
        rm -f tracked/*
    else
        mkdir tracked
    fi
    if [ -d "tracked_trans" ] ; then
        rm -f tracked_trans/*
    else
        mkdir tracked_trans
    fi
    if [ -d "unprocessed" ] ; then
        rm -f unprocessed/*
    else
        mkdir unprocessed
    fi
}

gather_transactions () {
    transactions=()
    trans_results=`mysql -BN -u $mysql_user -p''$mysql_pwd'' -e "select trx_id,trx_mysql_thread_id,(unix_timestamp()-unix_timestamp(trx_started)) secs,user,substring_index(host,':',1) host,substring_index(host,':',-1) port from information_schema.innodb_trx it join information_schema.processlist ip on it.trx_mysql_thread_id=ip.id and locate(':',host) > 0"`
    if [ -n "$trans_results" ]; then
        while read trx_id thread_id secs user host port; do
            if [[ "$host" != [0-9]* ]]; then
                host=`resolveip -s $host`
            fi
            client_id=`printf "%s:%s" $host $port`
            trans_data=`printf "%s.%s.%s.%s.%s" $client_id $trx_id $thread_id $secs $user`
            transactions["$client_id"]="$trans_data"
        done <<< "$trans_results"
    fi
}

archive_tracked () {
    tracked_files='tracked/*'
    tracked_count=`ls tracked/ | wc -l`
    if [ $tracked_count -eq 0 ]; then
        return;
    fi
    for tracked_file in $tracked_files; do
        client_id="${tracked_file:8}"
        tracked_trans_file=`ls tracked_trans/$client_id.* 2>/dev/null`
        archived_trans_file=`ls tracked_trans/archive-$client_id.* 2>/dev/null`
        new_trans="${transactions[$client_id]}"
        if [ -z "$new_trans" ]; then
            if [ -n "$archived_trans_file" ]; then
                trans_info="${archived_trans_file:22}"
                rm -f $archived_trans_file
                mv $tracked_file archived/$trans_info
            elif [ -n "$tracked_trans_file" ]; then
                trans_info="${tracked_trans_file:14}"
                trans_seconds=`echo $trans_info | cut -d '.' -f 7`
                if [ $trans_seconds -ge $min_trans_seconds ]; then
                    rm -f $tracked_trans_file
                    > tracked_trans/archive-$trans_info
                else
                    rm -f $tracked_trans_file
                    rm -f $tracked_file
                fi
            fi
        else
            rm -f $tracked_trans_file
            > tracked_trans/$new_trans
        fi
    done
}

track_candidates () {
    candidate_files='candidates/*'
    candidate_count=`ls candidates/ | wc -l`
    if [ $candidate_count -eq 0 ]; then
        return;
    fi
    for candidate_file in $candidate_files; do
        client_id=${candidate_file:11}
        trans=${transactions[$client_id]}
        if [ -n "$trans" ]; then
            mv $candidate_file tracked/$client_id
            > tracked_trans/$trans
        fi
    done
}

remove_candidates () {
    rm -f candidates/*
}

# MAIN
cleanup
tcpdump -i $tcpdump_interface tcp port $tcpdump_port and not ip6 $tcpdump_options -Z $tcpdump_user -U -G $tcpdump_seconds -w unprocessed/raw.%Y%d%m%H%M%S &
while ( true ); do
    sleep $tcpdump_seconds
    tcpdump_logs='unprocessed/raw.*'
    tcplog_count=`ls unprocessed/raw.* | wc -l`
    tcplog_index=1
    if [ $tcplog_count -ge 2 ]; then
        gather_transactions
        for tcpdump_log in $tcpdump_logs; do
            if [ $tcplog_index -lt $tcplog_count ]; then
                tcpdump -s 65535 -x -n -q -tttt -r $tcpdump_log | pt-query-digest --type tcpdump --no-report --watch-server $watch_ip:$watch_port --timeline --output slowlog | ./process_digest.sh
                rm $tcpdump_log
            fi
            tcplog_index=$tcplog_index+1
        done
        archive_tracked
        track_candidates
        remove_candidates
    fi
done
