#!/bin/bash
# ./iperf-helper.sh <ethox-iperf-executable> <device> <target-ip> <temp-src> <temp-target> <outfile1> <outfile2> [client]
ETHOX=$1
DEV=$2
OTHER=$3
TMPSRC=$4
TMPDST=$5
OUTFILE1=$6
OUTFILE2=$7
CLIENT=$8

OWNMAC=$(ip -f link a show $DEV | grep -Po 'ether \K[\da-f:]+')

ETHOX_UDP="$ETHOX $DEV $TMPSRC $OWNMAC $OTHER"
ETHOX_TCP="$ETHOX $DEV $TMPSRC $OWNMAC $OTHER"
OTHER="${OTHER%/*}"
TMPDST="${TMPDST%/*}"

PORT=5001
UL=1460
TL=131072 # 128 KiB
N=10740000 #0 # 1 GiB

SLEEP_TIME=5

function bench {
    if [ -z $CLIENT ]; then
        echo "$1" | tee -a $3
        $1 | tee -a $3
        sleep $SLEEP_TIME
        echo "$2" | tee -a $3
        $2 | tee -a $3
    else
        sleep $SLEEP_TIME
        echo "$2" | tee -a $3
        $2 | tee -a $3
        echo "$1" | tee -a $3
        $1 | tee -a $3
    fi
}

function udp-benches {
    bench "$ETHOX_UDP -s $PORT --udp" "$ETHOX_UDP -c $TMPDST $PORT -l $UL -n $N --udp" $1
    bench "iperf3 -s -1" "iperf3 -c $OTHER -u -n $N -b 0" $1
}

function iperf-server {
    echo "iperf -s"
    if [ `uname -m` = "riscv64" ]; then
        iperf -s -P 1
    else
        iperf -s &
        IPERF_PID=$!
        nc -l $(($PORT + 1))
        kill $IPERF_PID
    fi
}

function iperf-client {
    if [ `uname -m` = "armv7l" ]; then
        echo "$ETHOX_TCP -c $OTHER $PORT -l $TL -n $(($N / 10)) --tcp"
        $ETHOX_TCP -c $OTHER $PORT -l $TL -n $(($N / 10)) --tcp
    else
        echo "$ETHOX_TCP -c $OTHER $PORT -l $TL -n $N --tcp"
        $ETHOX_TCP -c $OTHER $PORT -l $TL -n $N --tcp
        sleep $SLEEP_TIME
        echo "" > /dev/tcp/$OTHER/$(($PORT + 1))
    fi
}

function tcp-benches {
    bench "iperf-server" "iperf-client" $1
    bench "iperf3 -s -1" "iperf3 -c $OTHER -n $N" $1
}

if [ -z $CLIENT ]; then
    echo "Server first version of the iperf benchmark helper script."
    echo "Be sure to start the client version on the target device."
else
    echo "Client first version of the iperf benchmark helper script."
    echo "Make sure the server version is already running on the target device."
fi

rm $OUTFILE1 $OUTFILE2

sudo ethtool -K "$DEV" rx on tx on
udp-benches $OUTFILE1
tcp-benches $OUTFILE1

sudo ethtool -K "$DEV" rx off tx off
tcp-benches $OUTFILE2

sudo ethtool -K "$DEV" rx on tx on
