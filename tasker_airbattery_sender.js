// ===== TASKER JAVASCRIPT ACTION FOR AIRBATTERY =====
// Name: AirBattery Android Sender
// Description: Send Android battery info to Mac AirBattery via built-in HTTP bridge

// ===== CONFIGURATION =====

// Must match your Mac's AirBattery group ID (23+ chars)
const GROUP_ID = "nc-abcdefghijklmnopqrst";

// Replace the first IP with your Mac's local IP Address on your main Wi-Fi network
// If you are using multiple networks with local network access, add their IPs separated by commas
// If you are using Tailscale, add your Tailscale IP or hostname from your Tailscale console
const MAC_IPS = ["192.168.12.34", "123.45.67.89", "rishus-macbook-pro.tailxxxxxx.ts.net"];

// Replace with your device nickname eg: "Rishu's Pixel"
const DEVICE_NAME = "Android Device";

// HTTP server port - DO NOT CHANGE from 7550 if you don't want to recompile AirBattery
const PORT = 7550;

// ===== CRYPTO UTILITIES =====

// Convert string to Uint8Array
function stringToUint8Array(str) {
    return new Uint8Array([...str].map(char => char.charCodeAt(0)));
}

// Convert Uint8Array to base64
function uint8ArrayToBase64(uint8Array) {
    let binary = '';
    for (let i = 0; i < uint8Array.length; i++) {
        binary += String.fromCharCode(uint8Array[i]);
    }
    return btoa(binary);
}

// Simple HMAC-SHA256 implementation for HKDF
async function hmac(key, data) {
    const cryptoKey = await crypto.subtle.importKey(
        'raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
    );
    const signature = await crypto.subtle.sign('HMAC', cryptoKey, data);
    return new Uint8Array(signature);
}

// HKDF-SHA256 implementation matching AirBattery
async function hkdf(inputKeyMaterial, salt, info, length) {
    // Extract phase
    const prk = await hmac(salt, inputKeyMaterial);

    // Expand phase
    const n = Math.ceil(length / 32);
    let okm = new Uint8Array(0);
    let t = new Uint8Array(0);

    for (let i = 1; i <= n; i++) {
        const tInfo = new Uint8Array(t.length + info.length + 1);
        tInfo.set(t);
        tInfo.set(info, t.length);
        tInfo[tInfo.length - 1] = i;

        t = await hmac(prk, tInfo);

        const newOkm = new Uint8Array(okm.length + t.length);
        newOkm.set(okm);
        newOkm.set(t, okm.length);
        okm = newOkm;
    }

    return okm.slice(0, length);
}

// Generate symmetric key using AirBattery's exact method
async function generateSymmetricKey(password) {
    if (password.length < 23) {
        throw new Error("Group ID must be at least 23 characters long");
    }

    // Extract password component: characters 15-22 (8 chars)
    const pass = password.substring(15, 23);
    // Extract salt: first 15 characters  
    const saltStr = password.substring(0, 15);

    const passwordData = stringToUint8Array(pass);
    const saltData = stringToUint8Array(saltStr);
    const info = new Uint8Array(0); // Empty info

    console.log(`🔑 Key derivation - Pass: "${pass}", Salt: "${saltStr}"`);

    return await hkdf(passwordData, saltData, info, 32);
}

// AES-GCM encryption matching AirBattery's format
async function encryptString(plaintext, password) {
    try {
        const key = await generateSymmetricKey(password);
        const cryptoKey = await crypto.subtle.importKey(
            'raw', key, 'AES-GCM', false, ['encrypt']
        );

        // Generate 12-byte IV (96 bits) for AES-GCM
        const iv = crypto.getRandomValues(new Uint8Array(12));
        const data = stringToUint8Array(plaintext);

        const encrypted = await crypto.subtle.encrypt(
            { name: 'AES-GCM', iv: iv },
            cryptoKey,
            data
        );

        // Combine IV + encrypted data (includes auth tag) like Apple's sealedBox.combined
        const result = new Uint8Array(iv.length + encrypted.byteLength);
        result.set(iv, 0);
        result.set(new Uint8Array(encrypted), iv.length);

        // Convert to base64
        return uint8ArrayToBase64(result);
    } catch (error) {
        console.log("❌ Encryption error: " + error);
        return null;
    }
}

// ===== ANDROID BATTERY INFO =====

function getAndroidBatteryInfo() {

    // Get battery level (Tasker variable %BATT)
    const batteryLevel = parseInt(global('BATT')) || 0;

    // Get charging status (Tasker variable %PACTIVE)
    const powerSource = global('PACTIVE') || 'none';
    const isCharging = (powerSource === 'ac' || powerSource === 'usb' || powerSource === 'wireless') ? 1 : 0;

    // Get battery saver state (Tasker variable %PSAVER)
    const batterySaver = global('PSAVER') || 'false';
    const lowPower = (batterySaver === 'true' || batterySaver === true);

    // Get device info using Tasker variables
    const deviceId = global('DEVID') || 'android_' + Date.now().toString(36);

    // Get current timestamp
    const now = Date.now() / 1000;

    console.log(`📱 Battery: ${batteryLevel}%, Charging: ${isCharging}, Device: ${DEVICE_NAME}, Low Power: ${lowPower}`);

    // Create Device object matching AirBattery's exact format
    return {
        hasBattery: true,
        deviceID: "android_" + deviceId,
        deviceType: "iPhone", // Use iPhone type for iPhone icon
        deviceName: DEVICE_NAME,
        deviceModel: "iPhone14,5", // iPhone 13 model identifier for newest icon
        batteryLevel: batteryLevel,
        isCharging: isCharging,
        isCharged: false,
        isPaused: false,
        acPowered: isCharging === 1,
        isHidden: false,
        lowPower: lowPower, // Now includes battery saver state
        parentName: "",
        lastUpdate: now,
        realUpdate: 0.0
    };
}

// ===== NETWORK COMMUNICATION =====

async function sendToAirBattery(message) {
    // Try each IP address until one works
    for (let i = 0; i < MAC_IPS.length; i++) {
        const ip = MAC_IPS[i];
        const url = `http://${ip}:${PORT}/airbattery`;

        try {
            console.log(`🌐 Trying ${i + 1}/${MAC_IPS.length}: ${url}`);
            console.log(`📤 Message: ${JSON.stringify(message)}`);

            const response = await fetch(url, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'User-Agent': 'Tasker-Android/1.0'
                },
                body: JSON.stringify(message)
            });

            const responseText = await response.text();
            console.log(`📥 Response: ${response.status} - ${responseText}`);

            if (response.ok) {
                console.log(`✅ Battery info sent successfully to AirBattery via ${ip}`);
                return true;
            } else {
                console.log(`❌ HTTP Error from ${ip}: ${response.status} - ${responseText}`);
                // Continue to next IP if this one failed
            }
        } catch (error) {
            console.log(`❌ Network error with ${ip}: ${error}`);
            // Continue to next IP if this one failed
        }
    }

    // If we get here, all IPs failed
    console.log("❌ All IP addresses failed");
    return false;
}

// ===== MAIN EXECUTION =====

async function main() {
    try {
        console.log("🚀 Starting AirBattery Android sender...");

        // Validate configuration
        if (GROUP_ID === "your-airbattery-group-id-here") {
            flash("❌ Please configure GROUP_ID in the script");
            return;
        }

        if (GROUP_ID.length < 23) {
            flash("❌ Group ID must be at least 23 characters long");
            return;
        }

        console.log("✅ Configuration valid");

        // Get Android battery info
        console.log("🔧 Getting battery info...");
        const batteryInfo = getAndroidBatteryInfo();
        const deviceArray = [batteryInfo];

        // Convert to JSON
        const jsonString = JSON.stringify(deviceArray);
        console.log("📱 Battery data: " + jsonString);

        // Encrypt the data using AirBattery's encryption
        console.log("🔐 Encrypting data...");
        const encryptedData = await encryptString(jsonString, GROUP_ID);
        if (!encryptedData) {
            console.log("❌ Encryption failed");
            return;
        }

        console.log("✅ Data encrypted successfully");
        console.log("🔧 Encrypted data length: " + encryptedData.length);

        // Create NCMessage matching AirBattery's format
        const message = {
            id: GROUP_ID.substring(0, 15), // First 15 chars as message ID
            sender: batteryInfo.deviceName || 'Android',
            command: "", // Empty command for battery data (like AirBattery does)
            content: encryptedData
        };

        console.log("🔧 Message created: " + JSON.stringify({ ...message, content: "[ENCRYPTED]" }));

        // Send to AirBattery's built-in HTTP bridge
        console.log("🌐 Sending to AirBattery...");
        const success = await sendToAirBattery(message);

        if (success) {
            console.log("✅ Battery info sent successfully to AirBattery");
            console.log("🎉 Success! Check AirBattery on your Mac.");
        } else {
            console.log("❌ Failed to send battery info");
        }

    } catch (error) {
        console.log("❌ Main error: " + error);
        console.log("❌ Error stack: " + error.stack);
    }
}

// ===== EXECUTION =====
console.log("📱 AirBattery Android Sender v2.0");
console.log("🔧 Debug: Script started");

// Test basic functionality first
try {
    console.log("🔧 Testing basic functions...");
    const battery = global('BATT');
    const power = global('PACTIVE');
    const device = global('DEVNAME');

    console.log("Battery level: " + battery);
    console.log("Power source: " + power);
    console.log("Device name: " + device);
    console.log("Group ID length: " + GROUP_ID.length);
    console.log("Mac IPs: " + MAC_IPS.join(", "));

} catch (e) {
    console.log("❌ Basic test failed: " + e);
}

main().catch(error => {
    console.log("❌ Uncaught error in main: " + error);
});
