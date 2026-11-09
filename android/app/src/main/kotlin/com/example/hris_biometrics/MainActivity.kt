package com.example.hris_biometrics

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.UnrecoverableKeyException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

class MainActivity : FlutterFragmentActivity() {
    private val channel = "app/biometric_guard"

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                val alias = call.argument<String>("alias") ?: "fp_guard"
                when (call.method) {
                    "createKey" -> result.success(createKey(alias))
                    "isKeyValid" -> result.success(keyState(alias))
                    "deleteKey" -> { deleteKey(alias); result.success(true) }
                    else -> result.notImplemented()
                }
            }
    }

    private fun createKey(alias: String): Boolean {
        return try {
            deleteKey(alias)
            val kg = KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            kg.init(
                KeyGenParameterSpec.Builder(
                    alias,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_CBC)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_PKCS7)
                    .setUserAuthenticationRequired(true)
                    .setInvalidatedByBiometricEnrollment(true)
                    .build()
            )
            kg.generateKey()
            true
        } catch (e: Throwable) {
            false
        }
    }

    // Returns: "valid" | "invalid" | "missing"
    private fun keyState(alias: String): String {
        return try {
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            val key = ks.getKey(alias, null) as? SecretKey ?: return "missing"
            Cipher.getInstance("AES/CBC/PKCS7Padding")
                .init(Cipher.ENCRYPT_MODE, key)
            "valid"
        } catch (e: KeyPermanentlyInvalidatedException) {
            "invalid"
        } catch (e: UnrecoverableKeyException) {
            "invalid"
        } catch (e: Throwable) {
            "valid"
        }
    }

    private fun deleteKey(alias: String) {
        try {
            KeyStore.getInstance("AndroidKeyStore")
                .apply { load(null) }.deleteEntry(alias)
        } catch (_: Throwable) {}
    }
}