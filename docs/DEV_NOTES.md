# Dev Notes — gotchas, protocol, and how to test

## Environment
- macOS 13+, Apple Silicon (arm64), Xcode CLI tools.
- Build: `swift build -c release` or `./build.sh release` (the latter produces
  `build/SyncLight Pro.app`, ad-hoc signed).

## ⚠️ The HID transport requirements (do not "simplify" these away)
`HIDTransport.swift` only works when **all** of these hold. Each was discovered
the hard way — `IOHIDDeviceSetReport` returns success otherwise but the device
does nothing, and no input reports arrive.

1. **Open via the IORegistry, not IOHIDManagerCopyDevices.**
   ```swift
   var iter: io_iterator_t = 0
   let m = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
   m["Manufacturer"] = "ROBOBLOQ"
   IOServiceGetMatchingServices(kIOMainPortDefault, m, &iter)
   // for each entry:
   let dev = IOHIDDeviceCreate(kCFAllocatorDefault, entry)
   ```
   Choose the vendor interface `usagePage == 0xFF00 && usage == 1`.

2. **Custom CFRunLoopMode** (hidapi's trick), pumped on a bg thread:
   ```swift
   let mode = CFRunLoopMode("SYNCLIGHT_HID_\(ptr)" as CFString)
   IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), mode.rawValue)
   while !stop { CFRunLoopRunInMode(mode, 0.5, false) }
   ```
   `kCFRunLoopDefaultMode` did NOT deliver input reports.

3. **Input buffer size = 64** (`MaxInputReportSize`), pointer kept alive.

4. **Writes: no leading report-id byte.**
   ```swift
   IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, frame, frame.count)
   ```
   (`frame` starts with `0x52 0x42` = "RB"). hidapi strips `data[0]` when report
   id is 0; sending `[0] + frame` also works but the clean form is the above.

5. **Color payload includes lamps:**
   `[1, r, g, b, lamps, lamps+1, 0, 0, 0, 254]`, action 134.
   Short form `[1,r,g,b,254]` leaves the strip off.

## Device facts (this unit)
- VID/PID: `0x1A86 / 0xFE07`, manufacturer string `ROBOBLOQ`.
- Interfaces: usagePage `0xFF00`, usage `1` is the vendor one we use.
- Descriptor: MaxInput=64, MaxOutput=64, MaxFeature=0.
- Info reply (byte offsets in the 64-byte report):
  `lamps=[11]`, `displaySize=[8]`, `uuid=[12..<20]`, `fw=[21].[22].[23]`,
  `id=[5..<8]`. Example: `id=000503 uuid=cdab74531abc5bbb fw=1.7.3
  lamps=112 display=34`.

## Testing without the GUI
Compile the core files + a scratch `main.swift`:

```bash
cat > /tmp/main.swift <<'EOF'
import Foundation
let t = HIDTransport()
let d = LightDriver(transport: t)
guard d.connect() else { print("FAIL"); exit(1) }
print("id=\(d.meta.id) uuid=\(d.meta.uuid) fw=\(d.meta.firmware) lamps=\(d.meta.lampsAmount)")
func pump(_ s: Double){ RunLoop.current.run(until: Date().addingTimeInterval(s)) }
d.setBrightness(200); pump(0.3)
d.setColor(r:255,g:0,b:0); pump(1.2)
d.setColor(r:0,g:0,b:255); pump(1.2)
d.turnOff()
EOF
cd SyncLightPro
swiftc -O Sources/SyncLightPro/HIDTransport.swift \
        Sources/SyncLightPro/RobobloqProtocol.swift \
        Sources/SyncLightPro/LightDriver.swift /tmp/main.swift -o /tmp/drvtest
/tmp/drvtest
```

If `lamps=0`, the info reply didn't arrive → re-check requirements 2 & 3.

## Comparing against Node (golden reference)
node-hid/hidapi is the known-good implementation. A Node script that lights the
lamp:
```js
const HID = require('node-hid');
const dev = new HID.HID(HID.devices().filter(x=>x.manufacturer==='ROBOBLOQ')[0].path);
const ck=b=>b.reduce((a,x)=>a+x,0)%256;
const p=[1,255,0,0,112,113,0,0,0,254];
const b=Buffer.alloc(5+p.length+1);
b.write('RB',0,2); b[2]=b.length; b[3]=1; b[4]=134;
p.forEach((v,i)=>b[5+i]=v); b[b.length-1]=ck([...b.slice(0,b.length-1)]);
dev.write(Buffer.concat([Buffer.from([0]), b]));
```
If Node lights it but Swift doesn't → the 5 transport requirements are the cause.

## One device at a time
Only one process can meaningfully drive the lamp. Close the original SyncLight
app, the GUI build of SyncLight Pro, and any leftover node/`node-hid` scripts
before testing (check with `ps aux | grep -iE 'node|SyncLight|drv'`). The
system `IOHIDDevice` owner is fine; a user process holding it is not.
