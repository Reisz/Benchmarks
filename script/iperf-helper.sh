#!/bin/sh
# ./iperf-helper.sh <ethox-iperf-executable> <device> <target-ip> <outfile> [client]
ETHOX=$1
DEV=$2
OTHER=$3
OUTFILE=$4
CLIENT=$5

OWN=$(ip -f inet a show $DEV | grep -Po 'inet \K[\d.]+/\d+')
OWNMAC=$(ip -f link a show $DEV | grep -Po 'ether \K[\da-f:]+')

ETHOX="$ETHOX $DEV $OWN $OWNMAC $OTHER"
OTHER="${OTHER%/*}"

PORT=5001
L=1460
N=100000

function bench {
    if [ -z $CLIENT ]; then
        echo "$1" | tee -a $OUTFILE
        $1 | tee -a $OUTFILE
        sleep 1
        echo "$2" | tee -a $OUTFILE
        $2 | tee -a $OUTFILE
    else
        sleep 1
        echo "$2" | tee -a $OUTFILE
        $2 | tee -a $OUTFILE
        echo "$1" | tee -a $OUTFILE
        $1 | tee -a $OUTFILE
    fi
}

if [ -z $CLIENT ]; then
    echo "Server first version of the iperf benchmark helper script."
    echo "Be sure to start the client version on the target device."
else
    echo "Client first version of the iperf benchmark helper script."
    echo "Make sure the server version is already running on the target device."
fi

rm $OUTFILE

bench "$ETHOX -s $PORT --udp" "$ETHOX -c $OTHER $PORT -l $L -n $N --udp"
bench "iperf3 -s -1" "iperf3 -c $OTHER -n $N"
bench "iperf3 -s -1" "iperf3 -c $OTHER -u -n $N -b 0"
