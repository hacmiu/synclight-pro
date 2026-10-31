# Robobloq SyncLight HID Protocol (reverse-engineered)

> ⚠️ **READ FIRST — the original app has TWO separate protocol builders,
> picked by transport (verified in `app_extracted/.webpack/main/index.js`):**
>
> | Transport (`checkDeviceType`) | Builder module | Frame style |
> |---|---|---|
> | **`hid`** = USB LIGHT (VID `0x1A86`/PID `0xFE07`) and `cdc`/`hid` group | **60895** | **Simple "RB" + direct action** (`setSectionLED:134`, `setBrightness:135`, …). No MAC, no `notSyncEffect`. |
> | **`ble`** (VID `0xFFAA`/PID `0x5555`) and **`dongle`** (VID `0xFFAA`/PID `0x5656`) | **62564** (via base 55883) | **20-byte MAC-based template** (`action.notSyncEffect = 2` + `subcmd`, MAC in bytes 5..10). |
>
> Selection happens in `ModuleConstructor.connect()` (module 64025):
> `"hid" → new (51545)` which sets `this.protocol = new r(60895)`;
> `"ble" → new (73914)` which sets `this.protocol = new r(62564)`;
> `"dongle" → new (57069)` extends 55883 (template).
>
> **So: simple "RB" + action = HID/USB. 20-byte template = BLE & dongle.**
> `RobobloqProtocol.swift` (this project) mirrors the **60895 / HID** builder and
> was verified on real USB hardware. Do **not** switch the USB driver to the
> 20-byte template — the USB lamp ignores it (tried in `probe_live.swift`), and
> in the original app that builder is only ever used by the BLE/dongle classes.

Source: `app_extracted/.webpack/main/index.js` (minified), module 62564 (protocol builder),
51800 (VID/PID constants), 72299 (sequence id), 96439 (HID connect).

## Device IDs

| Kind       | VID (dec/hex)      | PID (dec/hex)      | Transport |
|------------|--------------------|--------------------|-----------|
| LIGHT      | 6790  / 0x1A86     | 65031 / 0xFE07     | HID       |
| KEYBOARD   | 5215  / 0x145F     | 825   / 0x0339     | HID       |
| MOUSE      | 5215  / 0x145F     | 887   / 0x0377     | HID       |
| BLE        | 65450 / 0xFFAA     | 21845 / 0x5555     | BLE       |
| DONGLE     | 65450 / 0xFFAA     | 22102 / 0x5656     | HID dongle|
| CDC        | -                  | 65036 / 0xFE0C     | Serial 115200 8N1 |

Manufacturer string filter: `"ROBOBLOQ"`.

## Frame layout (header "RB")

All HID commands are built as a byte buffer:

```
[0..1]  "RB"           header (0x52 0x43)
[2]     length         total buffer length (UInt8)
[3]     seqId          rolling id 1..254 (increment, wrap at 255 -> 1)
[4]     action         command opcode (see table)
[5..]   payload        command specific
[last]  checksum       sum(all bytes before) % 256
```

### Action opcodes (HID / USB builder = module 60895)
```
setSyncScreen      : 128   (stream of RGB triplets, real-time ambilight)
writeDeviceInfo    : 129
readDeviceInfo     : 130
readDeviceUUID     : 131
setLedEffect       : 133
setSectionLED      : 134
setBrightness      : 135
setAutoOff         : 137
setDynamicSpeed    : 138
setSoundSensitivity: 139
setExternalAudio   : 145
setOpenUrl         : 147
setLampsAmount     : 149
setWhiteBright     : 150
turnOffLight       : 151
setComputerRhythm  : 152
```
(BLE / dongle builder 62564 uses a *different* table: `dongleChildrenInfo:0`,
`notSyncEffect:2`, `setSyncScreenStatus:13`, `setSyncScreen:128`,
`setSectionLED:134`, `writeDeviceInfo:129`, … plus the 20-byte template below.)

## The "20-byte" setter template (action = notSyncEffect = 2) — BLE/dongle only

> ⚠️ Builder module **62564**, used only by the **BLE** (`ble`, 73914) and
> **dongle** (57069 / 55883) classes. The **USB light (HID, module 60895) does
> NOT use it** — see the table at the top. Kept here for reference only.

Most BLE-path setters share a 20-byte frame:

```
0  'R'
1  'B'
2  len = 20
3  seqId
4  0x02  (notSyncEffect)
5  mac[0]
6  mac[1]
7  mac[2]
8  mac[3]
9  mac[4]
10 mac[5]
11 subcmd   (see below)
12 arg0
13 arg1
14 arg2
15 subcmd   (repeated block starts -- device applies to 2 halves)
16 arg0
17 arg1
18 arg2
19 checksum
```

`mac` = 6-byte device identifier obtained from `getDeviceFullInfo()`
(response bytes 6..11 of the readDeviceInfo reply).

### subcmd values (byte 11 / byte 15)
```
2  -> brightness        arg0 = clamp(brightness, min 5)
3  -> section LED       arg0,arg1,arg2 = r,g,b  (static color / setSectionLED)
4  -> led effect        arg0 = effectIndex
   (effect type 3 uses subcmd 6 instead)
5  -> dynamic speed     arg0 = clamp(speed,5..100)
6  -> led effect type3
7  -> sound sensitivity arg0 = clamp(sens,5..100)
8  -> led quantity      arg0<<8|arg1 = count (UInt16BE in bytes 12..13)
9  -> device location   arg0 = location code
10 -> edge number       arg0
11 -> power direction   arg0
12 -> line sequence     arg0, arg1
13 -> sync screen status arg0 = on/off
17 -> open url          arg0 = url index
24 -> white brightness  arg0, arg1
```
(For subcmds that only take one value, byte 13/14 = 0xFF, 0xFF. The block is
duplicated at bytes 15..18 so both halves of the frame carry the same value.)

## Special frames

### readDeviceInfo  (getDeviceFullInfo / getDeviceInfo)
```
alloc(6)
0 'R' 1 'B' 2 6 3 seqId 4 130 5 checksum
```
Response (concatenated from HID data events until next frame starts with "RB"):
```
[6..11]  mac (6 bytes)
[12..14] firmware version  major.minor.patch
[8]      displaySize
[15..18] device id (hex string)   // readUInt16BE(15) + readUInt8(17)
[20]     lampsAmount
[21]     location
[22]     installationMethod
[23]     wireMap code
[24]     edgeNumber
[30]     whiteColorDriver
```

### setSyncScreen (real-time color stream, action = 128)
```
length = 10 + payload.length
0 'R' 1 'B' 2 length 3 seqId 4 128
5 unknown  6 unknown  7 unknown  8 unknown
9..  RGB triplets (payload)
last = checksum
```
This is the ambilight path: app sends a stream of averaged screen colors.

### setAutoOff (action = 137)  len 8
```
0 'R' 1 'B' 2 8 3 seqId 4 137 5 arg0 6 arg1 7 checksum
```

### setExternalAudio (action = 145) len 8
```
... 4 145  5..6 UInt16BE(value)  7 checksum
```

## HID write mechanics

- Output report id = **0** is prepended to every written buffer
  (`u(x)`: alloc len+1, byte0=0, copy x at offset 1).
- If buffer > 64 bytes it is split into 64-byte chunks, each chunk also
  gets the report-id-0 prefix.
- Write via `HIDDevice.write` (interrupt OUT).
- Reads arrive async on `data` events; a frame starts when first 2 bytes == "RB";
  otherwise append to the last frame (continuation).

## Response parsing for write()/writeWithoutResponse()
- `write`: find response whose **byte[5] == action** (echo), default = 50 x `0x04`.
- `writeWithoutResponse`: find response whose **byte[3] == seqId**.

## Color handling
- wireMap default "RGB"; channels may be reordered per device (`wireMap`).
- `convertToBlack(rgb, threshold)` -> zero near-black to avoid glow bleed.
- Section LED sends up to 55 bytes per `setSectionLED` chunk (chunked for long strips).

## Real-time sync pipeline (old app)
1. `quiklight.getMonitors()` -> display list.
2. capture thread averages screen color at `samplingRate`.
3. averaged RGB -> `setSyncScreen` stream (chunked, split if > 57 bytes).
4. For devices requiring it, also `setSectionLED` with the averaged color.
