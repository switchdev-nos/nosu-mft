FROM ubuntu:bionic

RUN apt -yqq update --no-install-recommends >/dev/null
RUN apt install -yqq curl tar gzip dkms build-essential debhelper
