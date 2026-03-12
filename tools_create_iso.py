#!/usr/bin/env python3
import os
import struct
from datetime import datetime, timezone

SECTOR_SIZE = 2048


def both_endian_16(v: int) -> bytes:
    return struct.pack('<H', v) + struct.pack('>H', v)


def both_endian_32(v: int) -> bytes:
    return struct.pack('<I', v) + struct.pack('>I', v)


def iso_datetime_17(dt: datetime) -> bytes:
    s = dt.strftime('%Y%m%d%H%M%S')
    return s.encode('ascii') + b'00' + struct.pack('b', 0)


def dir_datetime_7(dt: datetime) -> bytes:
    year = dt.year - 1900
    return bytes([year, dt.month, dt.day, dt.hour, dt.minute, dt.second, 0])


def make_dir_record(extent_lba: int, size: int, flags: int, ident: bytes, dt: datetime) -> bytes:
    body = bytearray()
    body += b'\x00'  # len placeholder
    body += b'\x00'  # ext attr len
    body += both_endian_32(extent_lba)
    body += both_endian_32(size)
    body += dir_datetime_7(dt)
    body += bytes([flags])
    body += b'\x00'  # file unit size
    body += b'\x00'  # interleave gap size
    body += both_endian_16(1)  # vol seq num
    body += bytes([len(ident)])
    body += ident
    if len(ident) % 2 == 0:
        body += b'\x00'
    body[0] = len(body)
    return bytes(body)


def write_sector(buf: bytearray, lba: int, data: bytes):
    off = lba * SECTOR_SIZE
    if len(data) > SECTOR_SIZE:
        raise ValueError('sector data too large')
    buf[off:off + len(data)] = data


def create_iso(boot_image_path: str, out_iso_path: str):
    boot_data = open(boot_image_path, 'rb').read()
    if len(boot_data) != 1474560:
        raise ValueError('Expected 1.44MB boot image (1474560 bytes)')

    pvd_lba = 16
    br_lba = 17
    term_lba = 18
    boot_catalog_lba = 19
    root_dir_lba = 20
    boot_image_lba = 21
    boot_image_sectors = len(boot_data) // SECTOR_SIZE
    lpath_lba = boot_image_lba + boot_image_sectors
    mpath_lba = lpath_lba + 1
    volume_sectors = mpath_lba + 1

    total_size = volume_sectors * SECTOR_SIZE
    iso = bytearray(total_size)
    now = datetime.now(timezone.utc).replace(tzinfo=None)

    # Primary Volume Descriptor
    pvd = bytearray(SECTOR_SIZE)
    pvd[0] = 1
    pvd[1:6] = b'CD001'
    pvd[6] = 1
    pvd[8:40] = b'CRISPY-FUNICULAR OS'.ljust(32, b' ')
    pvd[40:72] = b'CRISPY_OS'.ljust(32, b' ')
    pvd[80:88] = both_endian_32(volume_sectors)
    pvd[120:124] = both_endian_16(1)
    pvd[124:128] = both_endian_16(1)
    pvd[128:132] = both_endian_16(SECTOR_SIZE)
    pvd[132:140] = both_endian_32(SECTOR_SIZE)
    pvd[140:144] = struct.pack('<I', lpath_lba)
    pvd[144:148] = struct.pack('<I', 0)
    pvd[148:152] = struct.pack('>I', mpath_lba)
    pvd[152:156] = struct.pack('>I', 0)

    root_record = make_dir_record(root_dir_lba, SECTOR_SIZE, 2, b'\x00', now)
    pvd[156:156 + len(root_record)] = root_record

    pvd[190:318] = b'CRISPY FUNICULAR'.ljust(128, b' ')
    pvd[318:446] = b'CRISPY OS BOOTABLE ISO'.ljust(128, b' ')
    pvd[813:830] = iso_datetime_17(now)
    pvd[830:847] = iso_datetime_17(now)
    pvd[847:864] = iso_datetime_17(now)
    pvd[864:881] = b'00000000000000000'
    pvd[881] = 1
    write_sector(iso, pvd_lba, pvd)

    # Boot Record Descriptor (El Torito)
    br = bytearray(SECTOR_SIZE)
    br[0] = 0
    br[1:6] = b'CD001'
    br[6] = 1
    br[7:39] = b'EL TORITO SPECIFICATION'.ljust(32, b'\x00')
    br[71:75] = struct.pack('<I', boot_catalog_lba)
    write_sector(iso, br_lba, br)

    # Volume Descriptor Terminator
    term = bytearray(SECTOR_SIZE)
    term[0] = 255
    term[1:6] = b'CD001'
    term[6] = 1
    write_sector(iso, term_lba, term)

    # Boot catalog
    cat = bytearray(SECTOR_SIZE)
    validation = bytearray(32)
    validation[0] = 0x01
    validation[1] = 0x00
    validation[2:4] = b'\x00\x00'
    validation[4:28] = b'CRISPY ELTORITO'.ljust(24, b' ')
    validation[28:30] = b'\x00\x00'
    validation[30] = 0x55
    validation[31] = 0xAA
    checksum = 0
    for i in range(0, 32, 2):
        if i == 28:
            continue
        checksum = (checksum + struct.unpack('<H', validation[i:i+2])[0]) & 0xFFFF
    checksum = ((0x10000 - checksum) & 0xFFFF)
    validation[28:30] = struct.pack('<H', checksum)

    initial = bytearray(32)
    initial[0] = 0x88  # bootable
    initial[1] = 0x02  # 1.44MB floppy emulation
    initial[2:4] = struct.pack('<H', 0x0000)
    initial[4] = 0x00
    initial[5] = 0x00
    initial[6:8] = struct.pack('<H', 1)
    initial[8:12] = struct.pack('<I', boot_image_lba)

    cat[0:32] = validation
    cat[32:64] = initial
    write_sector(iso, boot_catalog_lba, cat)

    # Root directory sector (only . and ..)
    root = bytearray(SECTOR_SIZE)
    dot = make_dir_record(root_dir_lba, SECTOR_SIZE, 2, b'\x00', now)
    dotdot = make_dir_record(root_dir_lba, SECTOR_SIZE, 2, b'\x01', now)
    root[0:len(dot)] = dot
    root[len(dot):len(dot)+len(dotdot)] = dotdot
    write_sector(iso, root_dir_lba, root)

    # Path tables (root only)
    lpath = bytearray(SECTOR_SIZE)
    lpath[0] = 1
    lpath[1] = 0
    lpath[2:6] = struct.pack('<I', root_dir_lba)
    lpath[6:8] = struct.pack('<H', 1)
    lpath[8] = 0
    write_sector(iso, lpath_lba, lpath)

    mpath = bytearray(SECTOR_SIZE)
    mpath[0] = 1
    mpath[1] = 0
    mpath[2:6] = struct.pack('>I', root_dir_lba)
    mpath[6:8] = struct.pack('>H', 1)
    mpath[8] = 0
    write_sector(iso, mpath_lba, mpath)

    # Boot image payload
    boot_off = boot_image_lba * SECTOR_SIZE
    iso[boot_off:boot_off + len(boot_data)] = boot_data

    os.makedirs(os.path.dirname(out_iso_path), exist_ok=True)
    with open(out_iso_path, 'wb') as f:
        f.write(iso)


if __name__ == '__main__':
    import sys
    if len(sys.argv) != 3:
        print('Usage: tools_create_iso.py <boot_image_floppy> <output.iso>')
        raise SystemExit(1)
    create_iso(sys.argv[1], sys.argv[2])
