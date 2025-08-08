# AirBattery Android Integration Setup Guide

## Prerequisites

1. **AirBattery** installed and running on your Mac
2. **Tasker** app installed on your Android device
3. Both devices on the same WiFi network

## Step 1: Enable HTTP Bridge in AirBattery

Run this command in Terminal on your Mac to enable the built-in HTTP bridge:

```bash
defaults write com.lihaoyun6.AirBattery httpBridgeEnabled -bool true
```

Then restart AirBattery. You should see this message in Console:
```
🌐 HTTP bridge listening on port 7000 for Android devices
```

## Step 2: Get Your Group ID

1. Open AirBattery settings on your Mac
2. Go to the "Nearcast" section  
3. Copy your Group ID (it should be 23+ characters long)

## Step 3: Configure the Tasker Script

1. Open the `tasker_airbattery_sender.js` file
2. Update these variables:
   ```javascript
   const GROUP_ID = "nc-yP8RNnZFCSM71xus9axj"; // Paste your AirBattery Group ID
   const MAC_IP = "192.168.5.215"; // Your Mac's IP address
   ```

3. To find your Mac's IP address, run in Terminal:
   ```bash
   ifconfig | grep "inet " | grep -v 127.0.0.1
   ```
   or:
   Click the Wi-Fi icon in your menu bar while holding your option key

## Step 4: Create Tasker Task

1. Open Tasker on Android
2. Create a new Task: "AirBattery Sender"
3. Add Action → Code → JavaScriptlet
4. Copy and paste the entire `tasker_airbattery_sender.js` content
5. Save the task

## Step 5: Create Triggers (Optional)

Create profiles to automatically send battery info:

### Battery Level Change Trigger:
- **Profile**: State → Power → Battery Level
- **From**: 0, **To**: 100
- **Link to**: AirBattery Sender task

### Charging State Change Trigger:  
- **Profile**: State → Power → Power
- **Source**: Any
- **Link to**: AirBattery Sender task

### Periodic Update:
- **Profile**: Time → Every 5 minutes
- **Link to**: AirBattery Sender task

## Step 6: Test the Setup

1. Run the Tasker task manually
2. Check Tasker's log for messages like:
   ```
   ✅ Battery info sent successfully to AirBattery
   ```
3. Check AirBattery on your Mac - you should see your Android device appear!

## Troubleshooting

### "❌ Encryption failed"
- Make sure your Group ID is at least 23 characters long
- Verify the Group ID matches exactly between Mac and Android

### "❌ Network error" 
- Check that both devices are on the same WiFi
- Verify the Mac IP address is correct
- Make sure AirBattery is running with HTTP bridge enabled

### "❌ HTTP Error: 403 Forbidden"
- Group ID mismatch - double-check it matches your Mac's AirBattery settings

### "❌ HTTP Error: 404 Not Found"
- AirBattery HTTP bridge not enabled or not running
- Check the IP address and port (should be 7000)

### Android device not showing in AirBattery
- The device data is saved to `~/Library/Application Support/AirBattery/nearcast/Android.json`
- Make sure AirBattery nearcast is enabled and configured properly

## Advanced Configuration

### Custom Device Name
Modify the script to use a custom name:
```javascript
const deviceName = "My Android Phone"; // Instead of using global('DEVNAME')
```

### Send Notifications
You can also send notifications to your Mac:
```javascript
// Add this function and call it when battery is low
async function sendLowBatteryAlert() {
    const notification = {
        type: 1,
        title: "Low Battery Alert", 
        info: `Android battery at ${batteryLevel}%`,
        atta: ""
    };
    
    const encryptedData = await encryptString(JSON.stringify(notification), GROUP_ID);
    const message = {
        id: GROUP_ID.substring(0, 15),
        sender: "Android",
        command: "notify",
        content: encryptedData
    };
    
    await sendToAirBattery(message);
}
```

## What You'll See

Once set up correctly:
- Your Android device will appear in AirBattery alongside your other devices
- Battery level updates in real-time
- Charging status indicators work properly
- Device integrates seamlessly with AirBattery's widgets and dock display

Enjoy having your Android battery info integrated with AirBattery! 🎉
