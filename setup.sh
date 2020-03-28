#!/usr/bin/env bash
if [ "$EUID" -ne 0 ]
then
    echo -e "You need to run this script as root."
    exit 1
fi
apt-get install -y libjpeg8-dev \
    libpng-dev
make ilclient
make -j4
make install

