package com.pcassistant.app

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/** Builds and broadcasts the Wake-on-LAN magic packet (102 bytes). */
object WakeOnLan {
    fun send(macAddress: String, broadcastIp: String): Boolean {
        return try {
            val hex = macAddress.replace(":", "").replace("-", "").replace(".", "").trim()
            require(hex.length == 12) { "Invalid MAC" }
            val macBytes = ByteArray(6) { i -> hex.substring(i * 2, i * 2 + 2).toInt(16).toByte() }
            val packet = ByteArray(102)
            for (i in 0 until 6) packet[i] = 0xFF.toByte()
            for (rep in 0 until 16) {
                System.arraycopy(macBytes, 0, packet, 6 + rep * 6, 6)
            }
            val address = InetAddress.getByName(broadcastIp)
            for (port in listOf(9, 7)) {
                repeat(5) {
                    DatagramSocket().use { socket ->
                        socket.broadcast = true
                        socket.send(DatagramPacket(packet, packet.size, address, port))
                    }
                }
            }
            true
        } catch (e: Exception) {
            false
        }
    }
}
