package cloud.kosch.corpnet;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import java.nio.charset.StandardCharsets;
import java.security.KeyStore;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

public final class SecureKeyStore {
    private static final String ANDROID_KEYSTORE = "AndroidKeyStore";
    private static final String PREFS = "corpnet_secure_keys";
    private static final String ALIAS = "corpnet_ai_key_master_v1";

    private SecureKeyStore() {}

    private static SecretKey getOrCreateKey() throws Exception {
        KeyStore ks = KeyStore.getInstance(ANDROID_KEYSTORE);
        ks.load(null);
        if (ks.containsAlias(ALIAS)) {
            return ((KeyStore.SecretKeyEntry) ks.getEntry(ALIAS, null)).getSecretKey();
        }

        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE);
        generator.init(new KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build());
        return generator.generateKey();
    }

    public static void save(Context context, String provider, String value) throws Exception {
        String id = safeId(provider);
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (value == null || value.trim().isEmpty()) {
            prefs.edit().remove(id + "_ct").remove(id + "_iv").apply();
            return;
        }

        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey());
        byte[] ciphertext = cipher.doFinal(value.getBytes(StandardCharsets.UTF_8));
        prefs.edit()
                .putString(id + "_ct", Base64.encodeToString(ciphertext, Base64.NO_WRAP))
                .putString(id + "_iv", Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP))
                .apply();
    }

    public static String load(Context context, String provider) {
        try {
            String id = safeId(provider);
            SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            String ct = prefs.getString(id + "_ct", null);
            String iv = prefs.getString(id + "_iv", null);
            if (ct == null || iv == null) return "";

            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(),
                    new GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)));
            byte[] plain = cipher.doFinal(Base64.decode(ct, Base64.NO_WRAP));
            return new String(plain, StandardCharsets.UTF_8);
        } catch (Exception e) {
            return "";
        }
    }

    public static boolean has(Context context, String provider) {
        return !load(context, provider).isEmpty();
    }

    private static String safeId(String provider) {
        if (provider == null || provider.isEmpty()) return "default";
        return provider.replaceAll("[^a-zA-Z0-9_-]", "_");
    }
}
