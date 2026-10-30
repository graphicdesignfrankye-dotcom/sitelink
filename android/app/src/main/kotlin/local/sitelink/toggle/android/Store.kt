package local.sitelink.toggle.android

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import local.sitelink.core.AppSettings
import local.sitelink.core.SettingsCodec

/** Impostazioni in chiaro (senza token) e token in uno spazio cifrato con una chiave dell'Android Keystore. */
class Store(context: Context) {
    private val app = context.applicationContext
    private val plain = app.getSharedPreferences("settings", Context.MODE_PRIVATE)
    private val secrets by lazy {
        val key = MasterKey.Builder(app).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
        EncryptedSharedPreferences.create(
            app, "tokens", key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    fun load(): AppSettings? {
        val json = plain.getString("json", null) ?: return null
        return runCatching { SettingsCodec.fromJson(json) { secrets.getString("token.$it", null) } }.getOrNull()
    }

    fun save(s: AppSettings) {
        secrets.edit().apply { s.sites.forEach { putString("token.${it.id}", it.token) } }.apply()
        plain.edit().putString("json", SettingsCodec.toJson(s)).apply()
    }
}
