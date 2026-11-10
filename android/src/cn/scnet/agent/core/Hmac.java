package cn.scnet.agent.core;

import java.nio.charset.Charset;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * HMAC-SHA256（HPC OpenAPI 的 AK/SK 签名用）。
 *
 * ArkTS 那边不得不手写（`cryptoFramework.createMac('SHA256')` 实测与标准不一致），
 * Android 的 javax.crypto 是标准实现，直接调。
 *
 * 签名 message 的字段顺序固定：accessKey,timestamp,user —— 顺序变了平台就拒。
 */
public final class Hmac {

    private Hmac() {
    }

    public static byte[] sha256(byte[] data) {
        try {
            java.security.MessageDigest md = java.security.MessageDigest.getInstance("SHA-256");
            return md.digest(data);
        } catch (Exception e) {
            return new byte[0];
        }
    }

    public static byte[] hmacSha256(byte[] key, byte[] message) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key, "HmacSHA256"));
            return mac.doFinal(message);
        } catch (Exception e) {
            return new byte[0];
        }
    }

    public static String hex(byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            String h = Integer.toHexString(b & 0xff);
            if (h.length() == 1) {
                sb.append('0');
            }
            sb.append(h);
        }
        return sb.toString();
    }

    public static String hmacHex(String secret, String message) {
        Charset utf8 = Charset.forName("UTF-8");
        return hex(hmacSha256(secret.getBytes(utf8), message.getBytes(utf8)));
    }

    /** 平台签名用的 body：{"accessKey":"…","timestamp":"…","user":"…"} */
    public static String hpcSignMessage(String accessKey, String timestamp, String user) {
        return "{\"accessKey\":\"" + accessKey + "\",\"timestamp\":\"" + timestamp
                + "\",\"user\":\"" + user + "\"}";
    }

    /** RFC 4231 / NIST 向量自检（结果写日志，便于排查"签名被拒"）。 */
    public static boolean selfCheck() {
        String sha = hex(sha256("abc".getBytes(Charset.forName("UTF-8"))));
        boolean shaOk = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad".equals(sha);
        String mac = hmacHex("key", "The quick brown fox jumps over the lazy dog");
        boolean macOk = "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8".equals(mac);
        return shaOk && macOk;
    }
}
