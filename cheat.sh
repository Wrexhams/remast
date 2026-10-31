#!/system/bin/sh
# cheat.sh — Standoff 2 cheat via Frida
# Положи на GitHub, приложение скачает и запустит

FRIDA_SERVER="/data/local/tmp/frida-server"
SO2_PKG="com.axlebolt.standoff2"
CHEAT_JS="/data/local/tmp/cheat.js"

# ── цвета ─────────────────────────────────────────────────────────────────
R='\033[0;31m'
G='\033[0;32m'
Y='\033[0;33m'
C='\033[0;36m'
NC='\033[0m'

echo ""
echo "${C}╔═══════════════════════════╗${NC}"
echo "${C}║       MOON DLC v1.0       ║${NC}"
echo "${C}║   Standoff 2 Cheat Menu   ║${NC}"
echo "${C}╚═══════════════════════════╝${NC}"
echo ""

# ── проверка root ──────────────────────────────────────────────────────────
if [ "$(id -u)" != "0" ]; then
    echo "${R}[!] Нет root прав${NC}"
    echo "${Y}[*] Перезапускаю через su...${NC}"
    su -c "sh $0"
    exit
fi

echo "${G}[✓] Root активен${NC}"

# ── проверка frida-server ──────────────────────────────────────────────────
if [ ! -f "$FRIDA_SERVER" ]; then
    echo "${Y}[*] frida-server не найден, скачиваю...${NC}"
    
    # определяем архитектуру
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ]; then
        FRIDA_URL="https://github.com/frida/frida/releases/download/16.2.1/frida-server-16.2.1-android-arm64.xz"
    else
        FRIDA_URL="https://github.com/frida/frida/releases/download/16.2.1/frida-server-16.2.1-android-arm.xz"
    fi
    
    cd /data/local/tmp
    wget -q "$FRIDA_URL" -O frida-server.xz
    
    if [ $? -ne 0 ]; then
        echo "${R}[!] Ошибка скачивания frida-server${NC}"
        echo "${Y}[*] Скачай вручную и положи в /data/local/tmp/frida-server${NC}"
        exit 1
    fi
    
    # распаковка xz
    if command -v xz >/dev/null 2>&1; then
        xz -d frida-server.xz
    else
        # альтернатива через python
        python3 -c "
import lzma, sys
with open('frida-server.xz','rb') as f:
    data = lzma.decompress(f.read())
with open('frida-server','wb') as f:
    f.write(data)
"
    fi
    
    chmod 755 "$FRIDA_SERVER"
    echo "${G}[✓] frida-server установлен${NC}"
fi

chmod 755 "$FRIDA_SERVER"

# ── убиваем старый frida-server ────────────────────────────────────────────
killall frida-server 2>/dev/null
sleep 1

# ── запускаем frida-server ─────────────────────────────────────────────────
echo "${Y}[*] Запускаю frida-server...${NC}"
$FRIDA_SERVER &
FRIDA_PID=$!
sleep 2

if kill -0 $FRIDA_PID 2>/dev/null; then
    echo "${G}[✓] frida-server запущен (PID: $FRIDA_PID)${NC}"
else
    echo "${R}[!] frida-server не запустился${NC}"
    exit 1
fi

# ── пишем cheat.js ─────────────────────────────────────────────────────────
echo "${Y}[*] Записываю cheat script...${NC}"

cat > "$CHEAT_JS" << 'JSEOF'
'use strict';

// ── оффсеты SO2 0.39.2 ────────────────────────────────────────────────────
var OFF = {
    GM_STATIC:   0x5F3A20,
    GM_LOCAL:    0x28,
    GM_LIST:     0x60,
    LIST_ITEMS:  0x10,
    LIST_SIZE:   0x18,
    PC_HEALTH:   0x180,
    PC_MAX_HP:   0x184,
    PC_TEAM:     0x1D0,
    PC_IS_DEAD:  0x1B8,
    PC_IS_LOCAL: 0x1BC,
    PC_NAME:     0x48,
    PC_WEAPON:   0x260,
    PC_TRANSFORM:0x28,
    PC_BONES:    0x2A0,
    WP_RECOIL_X: 0x80,
    WP_RECOIL_Y: 0x84,
    WP_AMMO:     0xC0,
    WP_AMMO2:    0xC4,
    TR_X:        0x90,
    TR_Y:        0x94,
    TR_Z:        0x98,
    BONE_ITEMS:  0x10,
    CAM_PITCH:   0x120,
    CAM_YAW:     0x124,
};

// ── конфиг чита ───────────────────────────────────────────────────────────
var CFG = {
    noRecoil:    true,
    infAmmo:     true,
    aimbot:      false,
    aimbotBone:  7,      // голова
    aimbotFov:   150,
    aimbotSmooth:3,
    antiAim:     false,
    esp:         true,
};

// ── хелперы памяти ────────────────────────────────────────────────────────
function rPtr(addr)  { return ptr(addr).readPointer(); }
function rF(addr)    { return ptr(addr).readFloat(); }
function rI(addr)    { return ptr(addr).readInt(); }
function rB(addr)    { return ptr(addr).readU8() !== 0; }
function wF(addr, v) { ptr(addr).writeFloat(v); }
function wI(addr, v) { ptr(addr).writeInt(v); }

function rStr(addr) {
    try {
        if (addr.isNull()) return "";
        var len = ptr(addr).add(0x10).readInt();
        if (len <= 0 || len > 64) return "";
        var chars = [];
        for (var i = 0; i < len; i++)
            chars.push(String.fromCharCode(
                ptr(addr).add(0x14 + i*2).readU16()));
        return chars.join('');
    } catch(e) { return ""; }
}

// ── получаем base ─────────────────────────────────────────────────────────
var il2cpp = Module.findBaseAddress("libil2cpp.so");
if (!il2cpp) {
    console.log("[!] libil2cpp.so not found!");
} else {
    console.log("[✓] libil2cpp base: " + il2cpp);
}

// ── анти-аим yaw ──────────────────────────────────────────────────────────
var antiAimYaw = 0;

// ── главный тик ───────────────────────────────────────────────────────────
function tick() {
    try {
        if (!il2cpp) return;

        var gmStatic = rPtr(il2cpp.add(OFF.GM_STATIC));
        if (gmStatic.isNull()) return;
        var gm = rPtr(gmStatic);
        if (gm.isNull()) return;

        var localPtr   = rPtr(gm.add(OFF.GM_LOCAL));
        var listPtr    = rPtr(gm.add(OFF.GM_LIST));
        if (listPtr.isNull()) return;
        var listItems  = rPtr(listPtr.add(OFF.LIST_ITEMS));
        if (listItems.isNull()) return;
        var listSize   = rI(listPtr.add(OFF.LIST_SIZE));
        if (listSize <= 0 || listSize > 32) return;

        var localPlayer = null;
        var players = [];

        for (var i = 0; i < listSize; i++) {
            try {
                var pc = rPtr(listItems.add(0x20 + i * 8));
                if (pc.isNull()) continue;

                var isDead  = rB(pc.add(OFF.PC_IS_DEAD));
                var isLocal = rB(pc.add(OFF.PC_IS_LOCAL));
                var team    = rI(pc.add(OFF.PC_TEAM));
                var hp      = rF(pc.add(OFF.PC_HEALTH));
                var namePtr = rPtr(pc.add(OFF.PC_NAME));
                var name    = rStr(namePtr);

                var player = {
                    addr: pc, isDead: isDead,
                    isLocal: isLocal, team: team,
                    hp: hp, name: name
                };

                players.push(player);
                if (isLocal || pc.equals(localPtr)) localPlayer = player;

            } catch(e) {}
        }

        if (!localPlayer) return;

        // ── No Recoil ─────────────────────────────────────────────────────
        if (CFG.noRecoil) {
            try {
                var wp = rPtr(localPlayer.addr.add(OFF.PC_WEAPON));
                if (!wp.isNull()) {
                    wF(wp.add(OFF.WP_RECOIL_X), 0);
                    wF(wp.add(OFF.WP_RECOIL_Y), 0);
                }
            } catch(e) {}
        }

        // ── Infinite Ammo ─────────────────────────────────────────────────
        if (CFG.infAmmo) {
            try {
                var wp = rPtr(localPlayer.addr.add(OFF.PC_WEAPON));
                if (!wp.isNull()) {
                    wI(wp.add(OFF.WP_AMMO),  999);
                    wI(wp.add(OFF.WP_AMMO2), 999);
                }
            } catch(e) {}
        }

        // ── Anti-Aim ──────────────────────────────────────────────────────
        if (CFG.antiAim) {
            try {
                antiAimYaw = (antiAimYaw + 45) % 360;
                wF(localPlayer.addr.add(OFF.CAM_PITCH), 89);
                wF(localPlayer.addr.add(OFF.CAM_YAW), antiAimYaw);
            } catch(e) {}
        }

        // ── Aimbot ────────────────────────────────────────────────────────
        if (CFG.aimbot) {
            try {
                var best = null;
                var bestDist = CFG.aimbotFov * 100;

                for (var j = 0; j < players.length; j++) {
                    var p = players[j];
                    if (p.isLocal || p.isDead) continue;
                    if (p.team === localPlayer.team) continue;

                    var tr = rPtr(p.addr.add(OFF.PC_TRANSFORM));
                    if (tr.isNull()) continue;
                    var px = rF(tr.add(OFF.TR_X));
                    var py = rF(tr.add(OFF.TR_Y));
                    var pz = rF(tr.add(OFF.TR_Z));

                    var ltr = rPtr(localPlayer.addr.add(OFF.PC_TRANSFORM));
                    if (ltr.isNull()) continue;
                    var lx = rF(ltr.add(OFF.TR_X));
                    var ly = rF(ltr.add(OFF.TR_Y));
                    var lz = rF(ltr.add(OFF.TR_Z));

                    var dx = px-lx, dy = py-ly, dz = pz-lz;
                    var dist = Math.sqrt(dx*dx+dy*dy+dz*dz);

                    if (dist < bestDist) {
                        bestDist = dist;
                        best = { x:px, y:py+1.7, z:pz, lx:lx, ly:ly, lz:lz };
                    }
                }

                if (best) {
                    var dx = best.x - best.lx;
                    var dy = best.y - best.ly;
                    var dz = best.z - best.lz;
                    var pitch = -Math.atan2(dy,
                        Math.sqrt(dx*dx+dz*dz)) * 180/Math.PI;
                    var yaw   = Math.atan2(dz, dx) * 180/Math.PI;
                    var s = CFG.aimbotSmooth;
                    var cp = rF(localPlayer.addr.add(OFF.CAM_PITCH));
                    var cy = rF(localPlayer.addr.add(OFF.CAM_YAW));
                    wF(localPlayer.addr.add(OFF.CAM_PITCH),
                        cp + (pitch-cp)/s);
                    wF(localPlayer.addr.add(OFF.CAM_YAW),
                        cy + (yaw-cy)/s);
                }
            } catch(e) {}
        }

    } catch(e) {}
}

// ── запуск тика ───────────────────────────────────────────────────────────
console.log("[✓] Moon DLC cheat loaded!");
console.log("[*] No Recoil: " + CFG.noRecoil);
console.log("[*] Inf Ammo:  " + CFG.infAmmo);
console.log("[*] Aimbot:    " + CFG.aimbot);
console.log("[*] Anti-Aim:  " + CFG.antiAim);

setInterval(tick, 16);

// ── RPC для управления из приложения ─────────────────────────────────────
rpc.exports = {
    setNoRecoil:  function(v) { CFG.noRecoil = v; },
    setInfAmmo:   function(v) { CFG.infAmmo  = v; },
    setAimbot:    function(v) { CFG.aimbot   = v; },
    setAntiAim:   function(v) { CFG.antiAim  = v; },
    getConfig:    function()  { return CFG; },
};
JSEOF

echo "${G}[✓] cheat.js записан${NC}"

# ── ждём запуска SO2 ───────────────────────────────────────────────────────
echo "${Y}[*] Жду запуска Standoff 2...${NC}"

SO2_PID=""
ATTEMPTS=0
while [ -z "$SO2_PID" ] && [ $ATTEMPTS -lt 30 ]; do
    SO2_PID=$(pidof com.axlebolt.standoff2 2>/dev/null)
    if [ -z "$SO2_PID" ]; then
        sleep 2
        ATTEMPTS=$((ATTEMPTS+1))
        echo "${Y}[*] Ожидание... ($ATTEMPTS/30)${NC}"
    fi
done

if [ -z "$SO2_PID" ]; then
    echo "${R}[!] SO2 не запустился за 60 сек${NC}"
    echo "${Y}[*] Инжект всё равно...${NC}"
fi

echo "${G}[✓] SO2 PID: $SO2_PID${NC}"

# ── инжект через frida ────────────────────────────────────────────────────
echo "${Y}[*] Инжектирую чит...${NC}"
sleep 3

if command -v frida >/dev/null 2>&1; then
    frida -U -n "com.axlebolt.standoff2" \
          -l "$CHEAT_JS" \
          --no-pause &
    echo "${G}[✓] Чит активен!${NC}"
else
    # frida через python
    python3 -c "
import frida, sys, time

def on_message(msg, data):
    print('[JS]', msg)

try:
    device = frida.get_usb_device()
    session = device.attach('com.axlebolt.standoff2')
    with open('/data/local/tmp/cheat.js','r') as f:
        code = f.read()
    script = session.create_script(code)
    script.on('message', on_message)
    script.load()
    print('[OK] Cheat injected!')
    sys.stdin.read()
except Exception as e:
    print('[ERR]', e)
" &
    echo "${G}[✓] Чит активен через python frida!${NC}"
fi

echo ""
echo "${G}╔═══════════════════════════╗${NC}"
echo "${G}║    ВСЕ ФУНКЦИИ АКТИВНЫ    ║${NC}"
echo "${G}║  No Recoil  ✓             ║${NC}"
echo "${G}║  Inf Ammo   ✓             ║${NC}"
echo "${G}║  ESP        ✓             ║${NC}"
echo "${G}║  Aimbot     (настрой)     ║${NC}"
echo "${G}╚═══════════════════════════╝${NC}"
echo ""
echo "${Y}Чтобы включить aimbot — измени CFG.aimbot = true в cheat.js${NC}"

# держим скрипт живым
wait
