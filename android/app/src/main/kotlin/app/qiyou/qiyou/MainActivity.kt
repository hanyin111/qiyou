package app.qiyou.qiyou

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val alias = "app.qiyou.credentials.v1"
    private val accountFile get() = AtomicFile(File(noBackupFilesDir, "accounts.aes"))

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.qiyou/device")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "read" -> {
                            if (!accountFile.baseFile.exists()) result.success(null)
                            else {
                                val bytes = accountFile.readFully()
                                require(bytes.size > 28 && bytes[0].toInt() == 12)
                                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(1, 13)))
                                result.success(String(cipher.doFinal(bytes.copyOfRange(13, bytes.size)), Charsets.UTF_8))
                            }
                        }
                        "write" -> {
                            val value = call.arguments as? String ?: error("Invalid storage value")
                            require(value.toByteArray(Charsets.UTF_8).size <= 512000)
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.ENCRYPT_MODE, key())
                            val bytes = byteArrayOf(cipher.iv.size.toByte()) + cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
                            val stream = accountFile.startWrite()
                            try { stream.write(bytes); accountFile.finishWrite(stream) }
                            catch (error: Exception) { accountFile.failWrite(stream); throw error }
                            result.success(null)
                        }
                        "delete" -> { accountFile.delete(); result.success(null) }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("SECURE_STORAGE", "本机安全存储不可用", null)
                }
            }
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).build())
        return generator.generateKey()
    }
}
