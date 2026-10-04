import ipaddress, os, socket, struct, subprocess, sys, time

def checksum(data):
    if len(data)%2: data += b'\0'
    value = sum(struct.unpack('!%dH' % (len(data)//2), data))
    while value>>16: value = (value&65535)+(value>>16)
    return (~value)&65535

family = int(sys.argv[1])
source = ipaddress.ip_address('10.0.2.15' if family==4 else 'fd00:2::15').packed
target = ipaddress.ip_address('192.0.2.1' if family==4 else '2001:db8::1').packed
tcp = struct.pack('!HHIIBBHHH', 23456, 443, 1, 0, 5<<4, 2, 65535, 0, 0)
pseudo = source+target+(struct.pack('!BBH',0,6,len(tcp)) if family==4 else struct.pack('!I3xB',len(tcp),6))
tcp = tcp[:16]+struct.pack('!H',checksum(pseudo+tcp))+tcp[18:]
if family==4:
    ip = struct.pack('!BBHHHBBH4s4s',0x45,0,40,1,0,64,6,0,source,target)
    ip = ip[:10]+struct.pack('!H',checksum(ip))+ip[12:]
else:
    ip = struct.pack('!IHBB16s16s',6<<28,20,6,64,source,target)
frame = bytes.fromhex('9a559a559a55525400123456')+struct.pack('!H',0x0800 if family==4 else 0x86dd)+ip+tcp
frame = frame.ljust(60,b'\0')
a,b=socket.socketpair()
env=os.environ.copy()
env['LD_PRELOAD']=sys.argv[3]
env['VM_TEST_DENY_FAMILY']=str(family)
cmd=[sys.argv[2],'--foreground','--debug','--fd',str(b.fileno()),'--interface','tailscale0','--outbound-if4','tailscale0','--outbound-if6','tailscale0','--address','10.0.2.15','--address','fd00:2::15','--gateway','10.0.2.2','--gateway','fd00:2::2','--netmask','24','--dns','1.1.1.1','--dns','2606:4700:4700::1111','--tcp-ports','none','--udp-ports','none','--no-map-gw']
p=subprocess.Popen(cmd,pass_fds=[b.fileno()],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
b.close()
try:
    time.sleep(.3)
    a.sendall(struct.pack('!I',len(frame))+frame)
    try:
        output=p.communicate(timeout=3)[0].decode(errors='replace')
    except subprocess.TimeoutExpired:
        p.terminate()
        output=p.communicate()[0].decode(errors='replace')
        print(output)
        raise SystemExit('FAIL: passt did not stop')
    assert "Can't bind IPv%d TCP socket to interface tailscale0" % family in output
    assert p.returncode != 0
    print(f"OK: IPv{family} bind failure stops passt before connect()")
finally:
    if p.poll() is None: p.kill();p.wait()
    a.close()
