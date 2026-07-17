import IOBluetooth

enum BluetoothDeviceController {
    static func connect(address: String) -> Bool {
        guard let device = IOBluetoothDevice(addressString: address) else { return false }
        if device.isConnected() { return true }
        return device.openConnection() == kIOReturnSuccess
    }

    static func disconnect(address: String) -> Bool {
        guard let device = IOBluetoothDevice(addressString: address) else { return false }
        if !device.isConnected() { return true }
        return device.closeConnection() == kIOReturnSuccess
    }
}
