import SwiftUI
import CoreBluetooth

// BLEDevice class definition
class BLEDevice: Identifiable, ObservableObject {
    var id = UUID()
    var name: String
    var rssi: Int
    var peripheral: CBPeripheral
    @Published var isConnected: Bool = false // Make isConnected observable
    @Published var services: [CBService] = [] // Store discovered services

    init(name: String, rssi: Int, peripheral: CBPeripheral) {
        self.name = name
        self.rssi = rssi
        self.peripheral = peripheral
    }
}

// BLEManager class definition
class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var centralManager: CBCentralManager!
    @Published var devices = [BLEDevice]()
    @Published var readData: Data? // Store read data
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        } else {
            // Handle Bluetooth not available
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if let name = peripheral.name {
            let bleDevice = BLEDevice(name: name, rssi: RSSI.intValue, peripheral: peripheral)
            if !devices.contains(where: { $0.peripheral == peripheral }) {
                devices.append(bleDevice)
            }
        }
    }
    
    func connectToDevice(_ device: BLEDevice) {
        centralManager.connect(device.peripheral, options: nil)
    }
    
    func disconnectFromDevice(_ device: BLEDevice) {
        centralManager.cancelPeripheralConnection(device.peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if let index = devices.firstIndex(where: { $0.peripheral == peripheral }) {
            devices[index].isConnected = true
        }
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let index = devices.firstIndex(where: { $0.peripheral == peripheral }) {
            devices[index].isConnected = false
            devices[index].services = []
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            if let index = devices.firstIndex(where: { $0.peripheral == peripheral }) {
                devices[index].services = services
            }
        }
    }
    
    func readCharacteristic(_ characteristic: CBCharacteristic) {
        if let peripheral = characteristic.service?.peripheral {
            peripheral.readValue(for: characteristic)
        } else {
            print("Peripheral is nil.")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error reading characteristic value: \(error.localizedDescription)")
            return
        }
        if let value = characteristic.value {
            self.readData = value
        }
    }
}

// ContentView definition
struct ContentView: View {
    @ObservedObject var bleManager = BLEManager()
    
    var body: some View {
        NavigationView {
            List(bleManager.devices) { device in
                NavigationLink(destination: DeviceDetailView(device: device, bleManager: bleManager)) {
                    HStack {
                        Text(device.name)
                        Spacer()
                        Text("\(device.rssi) dBm")
                    }
                }
            }
            .navigationBarTitle("BLE Devices")
        }
    }
}

// ServiceDetailView definition
struct ServiceDetailView: View {
    @ObservedObject var bleManager: BLEManager
    var service: CBService
    @State private var readValue: String = "No data"
    
    var body: some View {
        VStack {
            Text("Service: \(service.uuid)")
                .font(.headline)
                .padding()
            List(service.characteristics ?? [], id: \.uuid) { characteristic in
                VStack(alignment: .leading) {
                    Text("Characteristic: \(characteristic.uuid)")
                    if characteristic.properties.contains(.read) {
                        Button(action: {
                            bleManager.readCharacteristic(characteristic)
                        }) {
                            Text("Read")
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
            }
            Text("Read Data: \(readValue)")
                .padding()
            Spacer()
        }
        .onReceive(bleManager.$readData) { data in
            if let data = data {
                self.readValue = data.map { String(format: "%02x", $0) }.joined()
            }
        }
        .presentationDetents([.fraction(0.5)])
    }
}

// DeviceDetailView definition
struct DeviceDetailView: View {
    @ObservedObject var device: BLEDevice
    @ObservedObject var bleManager: BLEManager
    @State private var selectedService: CBService?
    @State private var showServiceDetail = false
    
    var body: some View {
        VStack {
            Text("Device Name: \(device.name)")
            Text("RSSI: \(device.rssi) dBm")
            if !device.isConnected {
                Button(action: {
                    bleManager.connectToDevice(device)
                }) {
                    Text("Connect")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            } else {
                Button(action: {
                    bleManager.disconnectFromDevice(device)
                }) {
                    Text("Disconnect")
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                Text("Connected")
                    .foregroundColor(.green)
                
                List(device.services, id: \.uuid) { service in
                    Button(action: {
                        selectedService = service
                        showServiceDetail = true
                    }) {
                        Text("Service: \(service.uuid)")
                    }
                }
            }
        }
        .navigationBarTitle(device.name, displayMode: .inline)
        .sheet(isPresented: $showServiceDetail) {
            if let selectedService = selectedService {
                ServiceDetailView(bleManager: bleManager, service: selectedService)
            }
        }
    }
}
