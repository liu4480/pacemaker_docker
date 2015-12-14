#!/bin/bash

nodelist="$PCMK_NODE_LIST"

trap "stop; exit 0;" SIGTERM SIGINT 

status()
{
	prog="$1"
	if [ -z "$prog" ]; then
		prog="pacemakerd"
	fi

	pid=$(pidof $prog 2>/dev/null)
	rtrn=$?
	if [ $rtrn -ne 0 ]; then
		echo "$prog is stopped"
	else
		echo "$prog (pid $pid) is running..."
	fi
	return $rtrn
}

start()
{
	#if [ -n "$nodelist" ]; then
	#	pcs cluster setup --force --local --name k8master $nodelist
	#fi

	/usr/share/corosync/corosync start > /dev/null 2>&1
	mkdir -p /var/run

	export PCMK_debugfile=/var/log/pacemaker.log
	(pacemakerd &) & > /dev/null 2>&1
	sleep 5

	pid=$(pidof pacemakerd)
	if [ "$?" -ne 0 ]; then
		echo "startup of pacemaker failed"
		exit 1
	fi
	echo "$pid" > /var/run/pacemakerd.pid
}

stop()
{
	desc="Pacemaker Cluster Manager"
	prog="pacemakerd"
	shutdown_prog=$prog

	if ! status $prog > /dev/null 2>&1; then
	    shutdown_prog="crmd"
	fi

	cname=$(crm_node --name)
	crm_attribute -N $cname -n standby -v true -l reboot

	if status $shutdown_prog > /dev/null 2>&1; then
	    kill -TERM $(pidof $prog) > /dev/null 2>&1

	    while status $prog > /dev/null 2>&1; do
		sleep 1
		echo -n "."
	    done
	else
	    echo -n "$desc is already stopped"
	fi

	rm -f /var/lock/subsystem/pacemaker
	rm -f /var/run/${prog}.pid

	/usr/share/corosync/corosync stop > /dev/null 2>&1
	killall -q -9 'corosync'
	killall -q -9 'crmd stonithd attrd cib lrmd pacemakerd corosync'
}

echo "#! /usr/bin/python
import os
import sys
import yaml

def newconf(filepath, nodelist):
    if os.path.exists(filepath) == False:
        return -1
    content = '''totem {
    version: 2
    secauth: off
    cluster_name: docker
    transport: udpu
}\n\n'''
    nodes = nodelist.split()
    i = 1
    content = content + '''nodelist {\n'''
    for node in nodes:
        content = content + '''    node {
        ring0_addr: %s
        nodeid: %d
    }\n\n''' % (node,i)
        i = i + 1
    content = content + '}\n\n'
    content = content + '''quorum {
    provider: corosync_votequorum
}

logging {
    to_logfile: yes
    logfile: /var/log/corosync.log
    to_syslog: yes
}
'''
    f = open(filepath, 'w')
    f.write(content)
    f.close()
    print len(sys.argv)
newconf('/etc/corosync/corosync.conf', sys.argv[1])
" > write_conf.py
chmod +x write_conf.py
echo $nodelist
./write_conf.py "$nodelist"

start

while true; do
	status "pacemakerd" || exit 1
	status "corosync" || exit 1
	sleep 5
done

exit 0
#TODO trap SIGTERM and do a graceful shutdown
