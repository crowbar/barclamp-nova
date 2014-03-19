#!/bin/bash

export TEST_TAG=${TEST_TAG:="test"}
export OS_USERNAME=${OS_USERNAME:="admin"}
export OS_PASSWORD=${OS_PASSWORD:="crowbar"}
export OS_TENANT_NAME=${OS_TENANT_NAME:="admin"}
export OS_AUTH_URL=${OS_AUTH_URL:="http://192.168.126.3:5000/v2.0/"}
export OS_AUTH_STRATEGY=${OS_AUTH_STRATEGY:="keystone"}
echo "TEST_TAG: $TEST_TAG ,  perform ./cleanup.sh -t <TAG_NAME> in order to apply  another test objetcs filter"

while getopts ":t:" opt; do
  case $opt in
    t)
      echo "-t default TEST_TAG is set to, parameter: $OPTARG" >&2
      TEST_TAG=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Using default test keyword\tag: $TEST_TAG." >&2
      ;;
  esac
done

echo -e "Wiping out Nova instances..."
TMP_FILE=$(mktemp)
sshkey_file="/var/log/smoketest/nova-smoketest.pem"

nova list | grep "$TEST_TAG*"  | awk {'print $2'} | grep -iv "id" | grep -v '^$' > $TMP_FILE
exec 3<$TMP_FILE  || echo "\n\n\n No tagged instances found \n\n\n"
while read -u 3 LINE; do
    echo -e "Wiping instance: $LINE"
    nova delete $LINE
    while nova list | grep -q $LINE; do sleep 1; done
done
rm -f $TMP_FILE

neutron floatingip-list | awk {'print $2'} | grep -iv 'id' | grep -v '^$' > $TMP_FILE
exec 3<$TMP_FILE
ssh-agent -k
if [ -f "$sshkey_file" ]; then
    rm $sshkey_file && echo -e "SSH keyfile $sshkey_file removed"
fi

while read -u 3 LINE; do
    f_ip=$(neutron floatingip-list | grep $LINE | awk {'print $5'} | grep -v '^$')
    echo -e "Wiping out floating-ip: $LINE, and ssh key for floating_ip $f_ip"
    neutron floatingip-delete  $LINE
    ssh-keygen -f "/root/.ssh/known_hosts" -R "$f_ip" &>/dev/null
done
rm -f $TMP_FILE

nova keypair-list | grep "$TEST_TAG*"  | awk {'print $2'} | grep -v '^$' > $TMP_FILE
exec 3<$TMP_FILE
while read -u 3 LINE; do
    echo -e "Wiping out keypair: $LINE"
    nova keypair-delete $LINE
done
rm -f $TMP_FILE

neutron security-group-list  | grep "$TEST_TAG*"  | awk {'print $2'} | grep -iv "id" | grep -v '^$' > $TMP_FILE
exec 3<$TMP_FILE
while read -u 3 LINE; do
    echo -e "Wiping out security group: $LINE"
    neutron security-group-delete  $LINE
done
rm -f $TMP_FILE

nova flavor-list  | grep "$TEST_TAG*"  | awk {'print $4'} | grep -v '^$' > $TMP_FILE
exec 3<$TMP_FILE
while read -u 3 LINE; do
    echo -e "Wiping out flavor: $LINE"
    nova flavor-delete  $LINE
done
rm -f $TMP_FILE

nova volume-snapshot-list  | grep "$TEST_TAG*"  | awk {'print $2'} | grep -v '^$' > $TMP_FILE
exec 3<$TMP_FILE
while read -u 3 LINE; do
    echo -e "Wiping out snapshot: $LINE"
    nova volume-snapshot-delete  $LINE
done
rm -f $TMP_FILE

nova volume-list | grep "$TEST_TAG" | awk {'print $2'} |  grep -v '^$' > $TMP_FILE
exec 3<$TMP_FILE
while read -u 3 LINE; do
    echo -e "Wiping out volume: $LINE"
    nova volume-delete  $LINE
done
rm -f $TMP_FILE

nova image-list | grep "$TEST_TAG" | awk {'print $2'} |  grep -v '^$' > $TMP_FILE
exec 3<$TMP_FILE
while read -u 3 LINE; do
    echo -e "Wiping out image: $LINE"
    nova image-delete  $LINE
done
rm -f $TMP_FILE

