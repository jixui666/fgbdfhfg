#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Minimal Mach-O 64-bit parser for analysis of libuiopsersvc (no external deps)."""
import struct, sys, os

LC = {
    0x00000001:'LC_SEGMENT', 0x00000002:'LC_SYMTAB', 0x00000003:'LC_SYMSEG',
    0x00000004:'LC_THREAD', 0x00000005:'LC_UNIXTHREAD', 0x00000006:'LC_LOADFVMLIB',
    0x00000007:'LC_IDFVMLIB', 0x00000008:'LC_IDENT', 0x00000009:'LC_FVMFILE',
    0x0000000A:'LC_PREPAGE', 0x0000000B:'LC_DYSYMTAB', 0x0000000C:'LC_LOAD_DYLIB',
    0x0000000D:'LC_ID_DYLIB', 0x0000000E:'LC_LOAD_DYLINKER', 0x0000000F:'LC_ID_DYLINKER',
    0x00000010:'LC_PREBOUND_DYLIB', 0x00000011:'LC_ROUTINES', 0x00000012:'LC_SUB_FRAMEWORK',
    0x00000013:'LC_SUB_UMBRELLA', 0x00000014:'LC_SUB_CLIENT', 0x00000015:'LC_SUB_LIBRARY',
    0x00000016:'LC_TWOLEVEL_HINTS', 0x00000017:'LC_PREBIND_CKSUM', 0x00000018:'LC_LOAD_WEAK_DYLIB',
    0x00000019:'LC_SEGMENT_64', 0x0000001A:'LC_ROUTINES_64', 0x0000001B:'LC_UUID',
    0x0000001C:'LC_RPATH', 0x0000001D:'LC_CODE_SIGNATURE', 0x0000001E:'LC_SEGMENT_SPLIT_INFO',
    0x0000001F:'LC_REEXPORT_DYLIB', 0x00000020:'LC_LAZY_LOAD_DYLIB', 0x00000021:'LC_ENCRYPTION_INFO',
    0x00000022:'LC_DYLD_INFO', 0x00000023:'LC_LOAD_UPWARD_DYLIB', 0x00000024:'LC_VERSION_MIN_MACOSX',
    0x00000025:'LC_VERSION_MIN_IPHONEOS', 0x00000026:'LC_FUNCTION_STARTS', 0x00000027:'LC_DYLD_ENVIRONMENT',
    0x00000028:'LC_MAIN', 0x00000029:'LC_DATA_IN_CODE', 0x0000002A:'LC_SOURCE_VERSION',
    0x0000002B:'LC_DYLIB_CODE_SIGN_DRS', 0x0000002C:'LC_ENCRYPTION_INFO_64',
    0x0000002D:'LC_LINKER_OPTION', 0x0000002E:'LC_LINKER_OPTIMIZATION_HINT',
    0x0000002F:'LC_VERSION_MIN_TVOS', 0x00000030:'LC_VERSION_MIN_WATCHOS', 0x00000031:'LC_NOTE',
    0x00000032:'LC_BUILD_VERSION', 0x00000033:'LC_DYLD_EXPORTS_TRIE', 0x00000034:'LC_DYLD_CHAINED_FIXUPS',
}

def uleb(data, off):
    r = 0; s = 0
    while True:
        b = data[off]; off += 1
        r |= (b & 0x7F) << s
        if not (b & 0x80): break
        s += 7
    return r, off

def cstr(data, off):
    e = data.find(b'\x00', off)
    if e < 0: return data[off:].decode('latin1'), len(data)
    return data[off:e].decode('latin1'), e + 1

class MachO:
    def __init__(self, path):
        self.path = path
        self.data = open(path, 'rb').read()
        if self.data[:4] == b'\xca\xfe\xba\xbe':
            self.fat = True
            n = struct.unpack('>I', self.data[4:8])[0]
            self.slices = []
            for i in range(n):
                cpu, sub, off, size, _ = struct.unpack('>IIIII', self.data[8+20*i:8+20*i+20])
                self.slices.append((cpu, sub, off, size))
            # pick arm64 slice (cpu 0x0100000C)
            arm = [s for s in self.slices if s[0] == 0x0100000C]
            sl = arm[0] if arm else self.slices[0]
            self.base = sl[2]
            self.data = self.data[sl[2]:sl[2]+sl[3]]
            self.fat = True
        else:
            self.fat = False
            self.base = 0
        self.magic, self.cpu, self.sub, self.filetype, self.ncmds, self.sizeofcmds, self.flags, _ = struct.unpack('<IIiiIIII', self.data[:32])
        assert self.magic == 0xFEEDFACF, 'not a 64-bit LE Mach-O'
        self.segments = []
        self.sections = []
        self.dylibs = []
        self.symtab = None
        self.dysymtab = None
        self.dyldinfo = None
        self.uuid = None
        self.cryptid = None
        self.funcstarts = None
        self.main = None
        self.rpaths = []
        self.buildver = None
        self.export_trie = None
        off = 32
        for _ in range(self.ncmds):
            cmd, cmdsize = struct.unpack('<II', self.data[off:off+8])
            body = self.data[off+8:off+cmdsize]
            name = LC.get(cmd, '0x%08X' % cmd)
            if cmd == 0x19:  # LC_SEGMENT_64
                segname = body[:16].split(b'\x00')[0].decode('latin1')
                vmaddr, vmsize, fileoff, filesize, maxp, initp, nsects, sflags = struct.unpack_from('<QQQQIIII', body, 16)
                self.segments.append(dict(name=segname, vmaddr=vmaddr, vmsize=vmsize,
                                          fileoff=fileoff, filesize=filesize, sflags=sflags))
                so = 64
                for _ in range(nsects):
                    sn = body[so:so+16].split(b'\x00')[0].decode('latin1')
                    sg = body[so+16:so+32].split(b'\x00')[0].decode('latin1')
                    addr, size, foff, align, reloff, nreloc, sflags, r1, r2, r3 = struct.unpack_from('<QQIIIIIIII', body, so+32)
                    self.sections.append(dict(name=sn, seg=sg, addr=addr, size=size,
                                              fileoff=foff, sflags=sflags))
                    so += 80
            elif cmd in (0x0C, 0x0D, 0x18 | 0x80000000, 0x1F | 0x80000000, 0x23 | 0x80000000, 0x20 | 0x80000000):
                noff = struct.unpack('<I', body[:4])[0]
                path = body[noff-8:].split(b'\x00')[0].decode('latin1')
                self.dylibs.append((name, path))
            elif cmd == 0x1C:
                off2 = struct.unpack('<I', body[:4])[0]
                self.rpaths.append(body[off2:].split(b'\x00')[0].decode('latin1'))
            elif cmd == 0x02:
                symoff, nsyms, stroff, strsize = struct.unpack('<IIII', body[:16])
                self.symtab = (symoff, nsyms, stroff, strsize)
            elif cmd == 0x0B:
                self.dysymtab = struct.unpack('<IIIIIIIIIIIIIIIIII', body[:72])
            elif cmd == 0x22:
                self.dyldinfo = struct.unpack('<IIIIIIIIII', body[:40])
            elif cmd == 0x1B:
                self.uuid = body[:16].hex().upper()
            elif cmd in (0x21, 0x2C):
                coff, csize, cid = struct.unpack('<III', body[:12])
                self.cryptid = cid
            elif cmd == 0x26:
                self.funcstarts = struct.unpack('<II', body[:8])
            elif cmd == 0x33 | 0x80000000:  # LC_DYLD_EXPORTS_TRIE
                self.export_trie = struct.unpack('<II', body[:8])
            elif cmd == 0x28:
                self.main = struct.unpack('<QQ', body[:16])
            elif cmd == 0x32:
                self.buildver = struct.unpack('<III', body[:12])
            off += cmdsize

    def seg_of_addr(self, addr):
        for s in self.segments:
            if s['vmaddr'] <= addr < s['vmaddr'] + s['vmsize']:
                return s
        return None

    def file_of_addr(self, addr):
        s = self.seg_of_addr(addr)
        if not s: return None
        f = s['fileoff'] + (addr - s['vmaddr'])
        if f > len(self.data): return None
        return f

    def symbols(self):
        if not self.symtab: return []
        symoff, nsyms, stroff, strsize = self.symtab
        out = []
        for i in range(nsyms):
            n_strx, n_type, n_sect, n_desc, n_value = struct.unpack('<IBBHQ', self.data[symoff+16*i:symoff+16*i+16])
            e = self.data.find(b'\x00', stroff + n_strx)
            nm = self.data[stroff+n_strx:e].decode('latin1')
            out.append((nm, n_type, n_sect, n_value))
        return out

    def exports(self):
        eo = es = None
        base = 0
        if self.dyldinfo:
            eo, es = self.dyldinfo[8], self.dyldinfo[9]
            # dyld info offsets are relative to __LINKEDIT file offset
            le = [s for s in self.segments if s['name'] == '__LINKEDIT']
            if le: base = le[0]['fileoff']
        elif self.export_trie is not None:
            eo, es = self.export_trie
            le = [s for s in self.segments if s['name'] == '__LINKEDIT']
            if le: base = le[0]['fileoff']
        if not eo or not es: return []
        out = []
        trie = base + eo
        if self.export_trie is not None:
            trie = eo  # absolute file offset for LC_DYLD_EXPORTS_TRIE
        def walk(off, prefix):
            p = trie + off
            ts, p = uleb(self.data, p)
            if ts:
                out.append(prefix)
            nc = self.data[p]; p += 1
            for _ in range(nc):
                s, p = cstr(self.data, p)
                child, p = uleb(self.data, p)
                walk(child, prefix + s)
        walk(0, '')
        return out

    def func_addrs(self):
        if not self.funcstarts: return []
        fo, fs = self.funcstarts
        base = self.data[fo:fo+fs]
        addrs = []; addr = 0; i = 0
        while i < fs:
            d, i = uleb(base, i)
            addr += d
            addrs.append(addr)
        return addrs

    def sec(self, seg, name):
        for s in self.sections:
            if s['seg'] == seg and s['name'] == name:
                return s
        return None

    def sec_bytes(self, seg, name):
        s = self.sec(seg, name)
        if not s: return b''
        return self.data[s['fileoff']:s['fileoff']+s['size']]

    def strings_in_sec(self, seg, name, minlen=4):
        b = self.sec_bytes(seg, name)
        out = []
        cur = bytearray()
        start = None
        for i, c in enumerate(b):
            if 0x20 <= c < 0x7F or c in (0x09,):
                if start is None: start = i
                cur.append(c)
            else:
                if len(cur) >= minlen:
                    out.append((start, bytes(cur).decode('latin1')))
                cur = bytearray(); start = None
        if len(cur) >= minlen:
            out.append((start, bytes(cur).decode('latin1')))
        return out

    def all_strings(self, minlen=6, regions=None):
        """scan printable runs over given regions (default: whole file)"""
        out = []
        if regions is None:
            regions = [(0, len(self.data))]
        for lo, hi in regions:
            cur = bytearray(); start = None
            for i in range(lo, min(hi, len(self.data))):
                c = self.data[i]
                if 0x20 <= c < 0x7F:
                    if start is None: start = i
                    cur.append(c)
                else:
                    if len(cur) >= minlen:
                        out.append((start, bytes(cur).decode('latin1')))
                    cur = bytearray(); start = None
            if len(cur) >= minlen:
                out.append((start, bytes(cur).decode('latin1')))
        return out

def dump(path, out):
    m = MachO(path)
    w = out.write
    w('=' * 100 + '\n')
    w('FILE: %s (%s, %d bytes)\n' % (path, 'FAT arm64' if m.fat else 'thin', len(m.data)))
    w('cputype=0x%X filetype=0x%X ncmds=%d flags=0x%X uuid=%s cryptid=%s\n' %
      (m.cpu, m.filetype, m.ncmds, m.flags, m.uuid, m.cryptid))
    if m.buildver:
        w('build_version platform=%d minos=0x%X sdk=0x%X\n' % m.buildver)
    w('\nSEGMENTS:\n')
    for s in m.segments:
        w('  %-16s vmaddr=0x%012X vmsize=0x%X fileoff=0x%X filesize=0x%X flags=0x%X\n' %
          (s['name'], s['vmaddr'], s['vmsize'], s['fileoff'], s['filesize'], s['sflags']))
    w('\nSECTIONS:\n')
    for s in m.sections:
        w('  %-12s %-22s addr=0x%012X size=0x%X fileoff=0x%X\n' % (s['seg'], s['name'], s['addr'], s['size'], s['fileoff']))
    w('\nDYLIB LOAD COMMANDS:\n')
    for kind, p in m.dylibs:
        w('  %-22s %s\n' % (kind, p))
    if m.rpaths:
        w('\nRPATHS: %s\n' % ', '.join(m.rpaths))
    if m.main:
        w('\nLC_MAIN: entryoff=0x%X\n' % m.main[0])
    syms = m.symbols()
    if syms:
        w('\nSYMBOLS (%d):\n' % len(syms))
        for nm, t, s, v in syms:
            w('  0x%012X t=0x%02X sect=%d %s\n' % (v, t, s, nm))
    exps = m.exports()
    if exps:
        w('\nEXPORTS (%d):\n' % len(exps))
        for e in sorted(exps):
            w('  _%s\n' % e)
    fa = m.func_addrs()
    if fa:
        w('\nFUNCTION STARTS (%d, text vmaddr base):\n' % len(fa))
        w('  ' + ' '.join('0x%X' % a for a in fa[:200]) + (' ...' if len(fa) > 200 else '') + '\n')
    # strings per notable section
    for seg, sec in (('__TEXT','__cstring'), ('__TEXT','__objc_methname'), ('__DATA','__objc_classname'),
                     ('__TEXT','__objc_methtype'), ('__TEXT','__oslogstring'), ('__TEXT','__ustring')):
        strs = m.strings_in_sec(seg, sec)
        if strs:
            w('\nSTRINGS %s.%s (%d):\n' % (seg, sec, len(strs)))
            for off, s in strs:
                w('  +0x%X  %s\n' % (off, s))
    # generic printable runs (whole file, excludes the above duplication but fine)
    w('\nDONE\n')

if __name__ == '__main__':
    paths = sys.argv[1:]
    out = open('macho_report.txt', 'w', encoding='utf-8')
    for p in paths:
        try:
            dump(p, out)
        except Exception as e:
            out.write('ERROR %s: %r\n' % (p, e))
    out.close()
    print('report written: macho_report.txt')
