//
//  Multipeer.swift
//  AirBattery
//
//  Created by apple on 2024/6/10.
//

import SwiftUI
import Foundation
import MultipeerKit
import Network

class MultipeerService: ObservableObject {
    @AppStorage("ncGroupID") var ncGroupID = ""
    @AppStorage("deviceName") var deviceName = "Mac"
    @AppStorage("httpBridgeEnabled") var httpBridgeEnabled = true  // Enable HTTP bridge by default
    let transceiver: MultipeerTransceiver
    private var httpListener: NWListener?

    init(serviceType: String) {
        let configuration = MultipeerConfiguration(
            serviceType: serviceType,
            peerName: getMacDeviceName(),
            defaults: ud,
            security: .default,
            invitation: .automatic)
        transceiver = MultipeerTransceiver(configuration: configuration)
        
        // Start the transceiver
        //transceiver.resume()
        
        // Handle received data
        transceiver.receive(Data.self) { data, peer in
            DispatchQueue.global().async {
                guard let message = try? JSONDecoder().decode(NCMessage.self, from: data) else {
                    print("Failed to decode message")
                    return
                }
                if message.id != self.ncGroupID.prefix(15) { return }
                switch message.command {
                case "resend":
                    var allDevices = AirBatteryModel.getAll()
                    allDevices.insert(ib2ab(InternalBattery.status), at: 0)
                    do {
                        let jsonData = try JSONEncoder().encode(allDevices)
                        guard let jsonString = String(data: jsonData, encoding: .utf8) else { return }
                        guard let data = encryptString(jsonString, password: self.ncGroupID) else { return }
                        let message = NCMessage(id: String(self.ncGroupID.prefix(15)), sender: systemUUID ?? self.deviceName, command: "", content: data)
                        netcastService.sendMessage(message, peerID: peer.id)
                    } catch {
                        print("Write JSON error：\(error)")
                    }
                    return
                case "trans":
                    print("Device received.")
                    return
                    /*if let jsonString = decryptString(message.content, password: self.ncGroupID) {
                        if let jsonData = jsonString.data(using: .utf8) {
                            if let device = try? JSONDecoder().decode(btdDevice.self, from: jsonData) {
                                let ret = BTTool.connect(mac: device.mac)
                                if ret {
                                    createNotification(title: "Device Connected".local,
                                                       message: String(format: "%@ from %@".local, device.name, peer.name))
                                } else {
                                    if let message = self.createInfo(type: 254, title: "Connection Failed".local, info: String(format: "cannot connect to your device!".local, device.name), atta: device.mac) {
                                        self.sendMessage(message, peerID: peer.id)
                                    }
                                }
                            }
                        } else {
                            print("Failed to convert JSON string to Data.")
                        }
                    }*/
                case "notify":
                    print("Info received.")
                    if let jsonString = decryptString(message.content, password: self.ncGroupID) {
                        if let jsonData = jsonString.data(using: .utf8) {
                            if let info = try? JSONDecoder().decode(NCNotification.self, from: jsonData) {
                                switch info.type {
                                case 1:
                                    createNotification(title: info.title, message: "\(info.info) (\(peer.name))")
                                case 255:
                                    createNotification(title: info.title, message: "\(peer.name) \(info.info)")
                                case 254:
                                    _ = BTTool.connect(mac: info.atta)
                                    createNotification(title: info.title, message: "\(peer.name) \(info.info)")
                                default:
                                    createNotification(title: info.title, message: info.info)
                                }
                            }
                        } else {
                            print("Failed to convert JSON string to Data.")
                        }
                    }
                case "":
                    print("Data received.")
                    if let jsonString = decryptString(message.content, password: self.ncGroupID) {
                        if let jsonData = jsonString.data(using: .utf8) {
                            let url = ncFolder.appendingPathComponent("\(message.sender).json")
                            try? jsonData.write(to: url)
                        } else {
                            print("Failed to convert JSON string to Data.")
                        }
                    }
                default:
                    print("Unknown command: \(message.command)")
                    if let info = self.createInfo(type: 255, title: "Unknown Command".local, info: String(format: "doesn't support command \"%@\"".local, message.command)) {
                        self.sendMessage(info, peerID: peer.id)
                    }
                    return
                }
            }
        }
        
        print("⚙️ Nearcast Group ID: \(ncGroupID)")
        
        // Setup HTTP bridge if enabled
        if httpBridgeEnabled {
            setupHTTPBridge()
        }
    }
    
    func resume() {
        transceiver.resume()
        print("ℹ️ Nearcast is running...")
    }
    
    func stop() {
        transceiver.stop()
        httpListener?.cancel()
        print("ℹ️ Nearcast has stopped")
    }

    func sendMessage(_ message: NCMessage, peerID: String? = nil) {
        guard let data = try? JSONEncoder().encode(message) else {
            print("Failed to encode message")
            return
        }
        let peers = removeDuplicatesPeer(peers: transceiver.availablePeers)
        if let peerID {
            transceiver.send(data, to: peers.filter({ $0.id == peerID }))
        } else {
            for peer in peers { transceiver.send(data, to: [peer]) }
        }
    }
    
    func refeshAll() {
        print("ℹ️ Pulling data...")
        let message = NCMessage(id: String(ncGroupID.prefix(15)), sender: systemUUID ?? self.deviceName, command: "resend", content: "")
        self.sendMessage(message)
    }
    
    func transDevice(device: Device, to name: String) {
        do {
            let btd = btdDevice(time: Date(), vid: "", pid: "", type: device.deviceType, mac: device.deviceID.replacingOccurrences(of: ":", with: "-").lowercased(), name: device.deviceName, level: device.batteryLevel)
            let jsonData = try JSONEncoder().encode(btd)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else { return }
            guard let data = encryptString(jsonString, password: self.ncGroupID) else { return }
            let message = NCMessage(id: String(self.ncGroupID.prefix(15)), sender: systemUUID ?? self.deviceName, command: "trans", content: data)
            for peer in transceiver.availablePeers.filter({ $0.name == name }) {
                self.sendMessage(message, peerID: peer.id)
            }
        } catch {
            print("Write JSON error：\(error)")
        }
    }
    
    func createInfo(type: Int = 0, title: String, info: String, atta: String = "") -> NCMessage? {
        do {
            let error = NCNotification(type: 0, title: title, info: info, atta: atta)
            let jsonData = try JSONEncoder().encode(error)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }
            guard let data = encryptString(jsonString, password: self.ncGroupID) else { return nil }
            return NCMessage(id: String(self.ncGroupID.prefix(15)), sender: systemUUID ?? self.deviceName, command: "notify", content: data)
        } catch {
            print("Write JSON error：\(error)")
        }
        return nil
    }
    
    // MARK: - HTTP Bridge for Android Integration
    
    private func setupHTTPBridge() {
        do {
            httpListener = try NWListener(using: .tcp, on: 7550)
            httpListener?.newConnectionHandler = { [weak self] connection in
                self?.handleHTTPConnection(connection)
            }
            httpListener?.start(queue: .main)
            print("🌐 HTTP bridge listening on port 7550 for Android devices")
        } catch {
            print("❌ Failed to start HTTP bridge: \(error)")
        }
    }
    
    private func handleHTTPConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self.processHTTPRequest(data, connection: connection)
            }
            
            if isComplete {
                connection.cancel()
            }
        }
    }
    
    private func processHTTPRequest(_ data: Data, connection: NWConnection) {
        guard let httpString = String(data: data, encoding: .utf8) else {
            sendHTTPResponse(connection: connection, status: "400 Bad Request", body: "Invalid data")
            return
        }
        
        // Parse HTTP request
        let lines = httpString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            sendHTTPResponse(connection: connection, status: "400 Bad Request", body: "Invalid request")
            return
        }
        
        // Handle OPTIONS for CORS
        if firstLine.hasPrefix("OPTIONS") {
            sendHTTPResponse(connection: connection, status: "200 OK", body: "")
            return
        }
        
        // Handle POST to /airbattery
        guard firstLine.hasPrefix("POST /airbattery") else {
            sendHTTPResponse(connection: connection, status: "404 Not Found", body: "Not found")
            return
        }
        
        // Extract JSON body
        if let emptyLineIndex = lines.firstIndex(of: ""),
           emptyLineIndex + 1 < lines.count {
            let jsonBody = lines[(emptyLineIndex + 1)...].joined(separator: "\r\n")
            
            if let jsonData = jsonBody.data(using: .utf8),
               let ncMessage = try? JSONDecoder().decode(NCMessage.self, from: jsonData) {
                
                // Validate group ID
                if ncMessage.id == String(ncGroupID.prefix(15)) {
                    // Process as if received via MultipeerKit
                    processReceivedMessage(ncMessage, fromAndroid: true)
                    sendHTTPResponse(connection: connection, status: "200 OK", body: "Message processed")
                } else {
                    sendHTTPResponse(connection: connection, status: "403 Forbidden", body: "Invalid group ID")
                }
            } else {
                sendHTTPResponse(connection: connection, status: "400 Bad Request", body: "Invalid JSON")
            }
        } else {
            sendHTTPResponse(connection: connection, status: "400 Bad Request", body: "No body")
        }
    }
    
    private func processReceivedMessage(_ message: NCMessage, fromAndroid: Bool = false) {
        // Same logic as the MultipeerKit receiver, but without peer parameter
        DispatchQueue.global().async {
            switch message.command {
            case "":
                print("📱 Android data received.")
                if let jsonString = decryptString(message.content, password: self.ncGroupID) {
                    if let jsonData = jsonString.data(using: .utf8) {
                        let url = ncFolder.appendingPathComponent("\(message.sender).json")
                        try? jsonData.write(to: url)
                        print("✅ Android battery data saved")
                    } else {
                        print("Failed to convert JSON string to Data.")
                    }
                }
            case "notify":
                print("📱 Android notification received.")
                if let jsonString = decryptString(message.content, password: self.ncGroupID) {
                    if let jsonData = jsonString.data(using: .utf8) {
                        if let info = try? JSONDecoder().decode(NCNotification.self, from: jsonData) {
                            createNotification(title: info.title, message: "\(info.info) (from Android)")
                        }
                    }
                }
            default:
                print("📱 Android command '\(message.command)' received")
            }
        }
    }
    
    private func sendHTTPResponse(connection: NWConnection, status: String, body: String) {
        let response = """
        HTTP/1.1 \(status)
        Content-Type: text/plain
        Content-Length: \(body.utf8.count)
        Access-Control-Allow-Origin: *
        Access-Control-Allow-Methods: POST, OPTIONS
        Access-Control-Allow-Headers: Content-Type
        
        \(body)
        """
        
        let data = response.data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

func removeDuplicatesPeer(peers: [Peer]) -> [Peer] {
    var seenIDs = Set<String>()
    let filteredPeers = peers.filter { peer in
        if seenIDs.contains(peer.id) {
            return false
        } else {
            seenIDs.insert(peer.id)
            return true
        }
    }
    return filteredPeers
}

struct NCMessage: Codable {
    let id: String
    let sender: String
    let command: String
    let content: String
}

struct NCNotification: Codable {
    /// 0 = normal
    /// 1 = normal error
    /// 254 = bt error
    /// 255 = unknow command
    let type: Int
    let title: String
    let info: String
    let atta: String
}
