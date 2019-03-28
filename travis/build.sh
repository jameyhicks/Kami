#!/bin/bash

git clone --depth 1 https://github.com/mit-plv/bbv /tmp/bbv
git clone --depth 1 https://github.com/tchajed/coq-record-update /tmp/coq-record-update
mkdir /tmp/build;
cp -r * /tmp/build;
cd /tmp/bbv; make
cd /tmp/coq-record-update; make
cd /tmp/build;
make
