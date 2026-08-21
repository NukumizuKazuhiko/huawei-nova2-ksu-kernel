#!/usr/bin/env python3
"""Build Huawei-nova2 device boot image v0 container from a gzip kernel.

The device kernel partition holds an Android boot image v0 container:
page1 (2048B) header + gzip kernel + zero-fill. page_size lives at
offset 36 (Huawei layout), kernel_size at offset 8.
"""
import struct
import sys


def build(kernel_path, out_path):
    with open(kernel_path, 'rb') as f:
        kdata = f.read()

    hdr = bytearray(2048)
    hdr[0:8] = b'ANDROID!'
    struct.pack_into('<I', hdr, 8, len(kdata))      # kernel_size
    struct.pack_into('<I', hdr, 12, 0x00480000)      # kernel_addr
    struct.pack_into('<I', hdr, 20, 0x08000000)      # ramdisk_addr
    struct.pack_into('<I', hdr, 28, 0x01300000)      # tags_addr
    struct.pack_into('<I', hdr, 36, 2048)            # page_size (Huawei offset)
    cmd = ('loglevel=4 coherent_pool=512K page_tracker=on '
           'slub_min_objects=12 '
           'unmovable_isolate1=2:192M,3:224M,4:256M '
           'printktimer=0xfff0a000,0x534,0x538 '
           'androidboot.selinux=enforcing buildvariant=user')
    hdr[64:64 + len(cmd)] = cmd.encode('ascii')

    boot = bytes(hdr) + kdata
    with open(out_path, 'wb') as f:
        f.write(boot)
    print('boot.img size:', len(boot))


if __name__ == '__main__':
    build(sys.argv[1], sys.argv[2])
