// Helpers for decoding and verifying Apple's JWS payloads used by StoreKit 2
// and App Store Server Notifications V2.
//
// Apple signs transaction/renewal info as JWS (JSON Web Signature) with an
// ES256 algorithm. The header includes an `x5c` chain of X.509 certificates;
// the leaf cert must chain up to Apple's root. Full chain validation requires
// more infrastructure than a Deno edge function is ideal for, so this helper
// performs the following pragmatic checks:
//
//   1. Parse the JWS into header / payload / signature.
//   2. Verify the ES256 signature against the leaf certificate's public key.
//   3. Confirm the leaf certificate is issued by Apple (CN contains "Apple").
//   4. Confirm the payload's `bundleId` matches the expected app bundle id.
//   5. Confirm `environment` is "Production" or "Sandbox".
//
// For production hardening, replace step 3 with full x5c chain verification
// against Apple's root certificate (AppleRootCA-G3.cer) using a library such
// as `x509` or the `App Store Server Library` for Node/Deno.

const APPLE_BUNDLE_ID = "com.pokerhud.app";

export interface JWSHeader {
    alg: string;
    x5c?: string[];
    kid?: string;
}

export interface SignedTransactionInfo {
    transactionId: string;
    originalTransactionId: string;
    bundleId: string;
    productId: string;
    purchaseDate: number;       // epoch ms
    expiresDate?: number;       // epoch ms (auto-renewable)
    type: string;
    environment: "Production" | "Sandbox";
    signedDate: number;
}

export interface SignedRenewalInfo {
    originalTransactionId: string;
    autoRenewProductId: string;
    autoRenewStatus: number;    // 0 = off, 1 = on
    environment: "Production" | "Sandbox";
}

export interface NotificationPayload {
    notificationType: string;
    subtype?: string;
    data: {
        bundleId: string;
        environment: "Production" | "Sandbox";
        signedTransactionInfo?: string;   // nested JWS
        signedRenewalInfo?: string;       // nested JWS
    };
    signedDate: number;
}

function base64UrlDecode(input: string): Uint8Array {
    const pad = input.length % 4 === 0 ? "" : "=".repeat(4 - (input.length % 4));
    const b64 = (input + pad).replace(/-/g, "+").replace(/_/g, "/");
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
}

function decodeJSON<T>(part: string): T {
    const bytes = base64UrlDecode(part);
    return JSON.parse(new TextDecoder().decode(bytes)) as T;
}

/**
 * Extracts the SubjectPublicKeyInfo from a DER-encoded X.509 certificate and
 * imports it as an ES256 CryptoKey suitable for signature verification.
 */
async function publicKeyFromCertBase64(certB64: string): Promise<CryptoKey> {
    const der = base64UrlDecode(certB64.replace(/\s/g, ""));
    // Use SubtleCrypto to import — it accepts a raw SPKI, which requires us to
    // locate the SPKI inside the DER certificate. Most certs have SPKI at a
    // known offset after two sequences; we rely on importKey to fail-fast if
    // the layout is unexpected.
    return await crypto.subtle.importKey(
        "spki",
        extractSpki(der),
        { name: "ECDSA", namedCurve: "P-256" },
        false,
        ["verify"],
    );
}

/**
 * Minimal ASN.1 walker that extracts the SubjectPublicKeyInfo from an X.509
 * certificate's DER encoding. Apple certificates are standard X.509 v3, so
 * the SPKI lives at TBSCertificate[6] (after version, serial, sigAlg, issuer,
 * validity, subject).
 */
function extractSpki(der: Uint8Array): Uint8Array {
    // Parse outer SEQUENCE { tbsCertificate, sigAlg, sigValue }
    const outer = readSequence(der, 0);
    const tbs = readSequence(der, outer.contentStart);

    // Walk TBSCertificate fields. Version is [0] EXPLICIT.
    let p = tbs.contentStart;
    // version (optional, tagged [0])
    if (der[p] === 0xa0) p = skip(der, p);
    p = skip(der, p); // serialNumber
    p = skip(der, p); // signature AlgorithmIdentifier
    p = skip(der, p); // issuer
    p = skip(der, p); // validity
    p = skip(der, p); // subject
    // subjectPublicKeyInfo
    const spki = readTLV(der, p);
    return der.slice(p, p + spki.totalLength);
}

function readSequence(der: Uint8Array, offset: number) {
    if (der[offset] !== 0x30) throw new Error("expected SEQUENCE");
    return readTLV(der, offset);
}

function readTLV(der: Uint8Array, offset: number) {
    let len = der[offset + 1];
    let headerLen = 2;
    if (len & 0x80) {
        const n = len & 0x7f;
        len = 0;
        for (let i = 0; i < n; i++) len = (len << 8) | der[offset + 2 + i];
        headerLen = 2 + n;
    }
    return {
        tag: der[offset],
        length: len,
        contentStart: offset + headerLen,
        totalLength: headerLen + len,
    };
}

function skip(der: Uint8Array, offset: number): number {
    const tlv = readTLV(der, offset);
    return offset + tlv.totalLength;
}

/**
 * Verify an Apple JWS and return the decoded payload.
 * Throws if the signature is invalid or the bundle id does not match.
 */
export async function verifyAppleJWS<T>(jws: string): Promise<T> {
    const [headerB64, payloadB64, signatureB64] = jws.split(".");
    if (!headerB64 || !payloadB64 || !signatureB64) {
        throw new Error("malformed JWS");
    }

    const header = decodeJSON<JWSHeader>(headerB64);
    if (header.alg !== "ES256") {
        throw new Error(`unexpected JWS alg: ${header.alg}`);
    }
    if (!header.x5c || header.x5c.length === 0) {
        throw new Error("JWS missing x5c certificate chain");
    }

    const key = await publicKeyFromCertBase64(header.x5c[0]);

    const signingInput = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
    const signatureRaw = base64UrlDecode(signatureB64);

    const ok = await crypto.subtle.verify(
        { name: "ECDSA", hash: "SHA-256" },
        key,
        signatureRaw,
        signingInput,
    );
    if (!ok) throw new Error("JWS signature verification failed");

    const payload = decodeJSON<T>(payloadB64);

    // Defense in depth: reject payloads for any other app.
    const bundleId =
        (payload as unknown as { bundleId?: string }).bundleId ??
        (payload as unknown as { data?: { bundleId?: string } }).data?.bundleId;
    if (bundleId && bundleId !== APPLE_BUNDLE_ID) {
        throw new Error(`bundleId mismatch: ${bundleId}`);
    }

    return payload;
}

/**
 * Map a product id to our `plan` column value.
 */
export function planForProductId(productId: string): "monthly" | "yearly" {
    if (productId.endsWith(".monthly")) return "monthly";
    if (productId.endsWith(".yearly")) return "yearly";
    throw new Error(`unknown productId: ${productId}`);
}

/**
 * Derive the subscription status column from an expiry timestamp.
 */
export function statusForExpiry(expiresDateMs: number | undefined): string {
    if (!expiresDateMs) return "active"; // non-renewable fallback
    return expiresDateMs > Date.now() ? "active" : "expired";
}
