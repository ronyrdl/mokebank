package com.example.moke_bank

import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val notifications by lazy { OperationNotifications(this) }
    private var cancellation: CancellationSignal? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        notifications.register(flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "moke_bank/biometrics")
            .setMethodCallHandler { call, result ->
                if (call.method == "authenticate") authenticate(result)
                else result.notImplemented()
            }
    }

    private fun authenticate(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.error("UNSUPPORTED", "La biometría requiere Android 11 o posterior.", null)
            return
        }
        if (cancellation != null) {
            result.error("BUSY", "Ya hay una verificación en curso.", null)
            return
        }

        val strength = BiometricManager.Authenticators.BIOMETRIC_STRONG
        val manager = getSystemService(BiometricManager::class.java)
        if (manager?.canAuthenticate(strength) != BiometricManager.BIOMETRIC_SUCCESS) {
            result.error("UNAVAILABLE", "Registra una huella compatible en los ajustes de Android o intenta más tarde.", null)
            return
        }

        val signal = CancellationSignal()
        cancellation = signal
        fun finish(accepted: Boolean) {
            if (cancellation !== signal) return
            cancellation = null
            result.success(accepted)
        }

        try {
            BiometricPrompt.Builder(this)
                .setTitle("Confirma la operación")
                .setSubtitle("Usa la biometría registrada en tu teléfono")
                .setAllowedAuthenticators(strength)
                .setNegativeButton("Cancelar", mainExecutor) { _, _ -> finish(false) }
                .build()
                .authenticate(signal, mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                        finish(true)
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        if (cancellation !== signal) return
                        if (errorCode == BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED ||
                            errorCode == BiometricPrompt.BIOMETRIC_ERROR_CANCELED) {
                            finish(false)
                        } else {
                            cancellation = null
                            result.error("AUTH_ERROR", errString.toString(), null)
                        }
                    }
                })
        } catch (error: RuntimeException) {
            cancellation = null
            result.error("AUTH_ERROR", "No se pudo iniciar la verificación biométrica.", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        notifications.onPermissionResult(requestCode, grantResults)
    }

    override fun onStop() {
        cancellation?.cancel()
        super.onStop()
    }
}
