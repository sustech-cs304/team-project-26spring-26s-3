import http from '@ohos.net.http';

import { XfyunFormulaConfig } from './XfyunFormulaConfig';

interface FormulaApiResponse {
  code?: number;
  message?: string;
  sid?: string;
  data?: {
    region?: FormulaRegion[];
  };
}

interface FormulaRegion {
  type?: string;
  recog?: {
    content?: string;
  };
}

export interface FormulaRecognitionResult {
  text: string;
  latex: string;
  sid: string;
}

const FORMULA_HOST = 'rest-api.xfyun.cn';
const FORMULA_URI = '/v2/itr';
const FORMULA_URL = `https://${FORMULA_HOST}${FORMULA_URI}`;
const FORMULA_AUTH_ALGORITHM = 'hmac-sha256';
const FORMULA_SIGNATURE_HEADERS = 'host date request-line digest';

export class XfyunFormulaService {
  constructor(private readonly config: XfyunFormulaConfig) {
  }

  async recognize(base64Image: string): Promise<FormulaRecognitionResult> {
    this.validateConfig();
    if (base64Image.trim().length === 0) {
      throw new Error('Formula image payload is empty.');
    }

    const requestBody = JSON.stringify({
      common: {
        app_id: this.config.appId
      },
      business: {
        ent: 'teach-photo-print',
        aue: 'raw'
      },
      data: {
        image: base64Image
      }
    });
    const date = this.buildRfc1123Date();
    const digest = `SHA-256=${this.encodeBase64(this.sha256(requestBody))}`;
    const authorization = this.buildAuthorization(date, digest);

    const client = http.createHttp();
    try {
      const response = await client.request(FORMULA_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json,version=1.0',
          'Host': FORMULA_HOST,
          'Date': date,
          'Digest': digest,
          'Authorization': authorization
        },
        readTimeout: 10000,
        connectTimeout: 10000,
        extraData: requestBody
      });

      const rawResult = this.readResponseText(response.result);
      if (response.responseCode !== 200) {
        throw new Error(`Formula request failed: HTTP ${response.responseCode} ${rawResult}`);
      }

      const payload = JSON.parse(rawResult) as FormulaApiResponse;
      if ((payload.code ?? -1) !== 0) {
        throw new Error(payload.message ?? `Formula service error code=${payload.code ?? -1}`);
      }

      const regions = payload.data?.region ?? [];
      const textParts: string[] = [];
      const latexParts: string[] = [];
      for (const region of regions) {
        if (region.type !== 'text') {
          continue;
        }
        const content = `${region.recog?.content ?? ''}`.trim();
        if (content.length === 0) {
          continue;
        }
        textParts.push(content);
        latexParts.push(...this.extractLatex(content));
      }

      const text = textParts.join('\n').trim();
      const latex = latexParts.join('\n').trim();
      if (text.length === 0 && latex.length === 0) {
        throw new Error('Formula service returned an empty recognition result.');
      }

      return {
        text,
        latex,
        sid: payload.sid ?? ''
      };
    } finally {
      try {
        client.destroy();
      } catch (_error) {
      }
    }
  }

  private validateConfig(): void {
    if (this.config.appId.trim().length === 0 ||
      this.config.apiKey.trim().length === 0 ||
      this.config.apiSecret.trim().length === 0) {
      throw new Error('XFYun formula config is incomplete. Fill appId/apiKey/apiSecret first.');
    }
  }

  private buildAuthorization(date: string, digest: string): string {
    const signatureOrigin =
      `host: ${FORMULA_HOST}\n` +
      `date: ${date}\n` +
      `POST ${FORMULA_URI} HTTP/1.1\n` +
      `digest: ${digest}`;
    const signature = this.encodeBase64(this.hmacSha256(signatureOrigin, this.config.apiSecret));
    return `api_key="${this.config.apiKey}", algorithm="${FORMULA_AUTH_ALGORITHM}", ` +
      `headers="${FORMULA_SIGNATURE_HEADERS}", signature="${signature}"`;
  }

  private buildRfc1123Date(): string {
    return new Date().toUTCString();
  }

  private extractLatex(content: string): string[] {
    const matches = content.match(/ifly-latex-begin([\s\S]*?)ifly-latex-end/g);
    if (matches === null) {
      return [];
    }

    const latexList: string[] = [];
    for (const match of matches) {
      const normalized = match
        .replace('ifly-latex-begin', '')
        .replace('ifly-latex-end', '')
        .trim();
      if (normalized.length > 0) {
        latexList.push(normalized);
      }
    }
    return latexList;
  }

  private sha256(text: string): Uint8Array {
    return this.digest(this.utf8Encode(text));
  }

  private hmacSha256(text: string, key: string): Uint8Array {
    const blockSize = 64;
    let keyBytes = this.utf8Encode(key);
    if (keyBytes.length > blockSize) {
      keyBytes = this.digest(keyBytes);
    }

    const normalizedKey = new Uint8Array(blockSize);
    normalizedKey.set(keyBytes.slice(0, blockSize));

    const outerPad = new Uint8Array(blockSize);
    const innerPad = new Uint8Array(blockSize);
    for (let index = 0; index < blockSize; index += 1) {
      outerPad[index] = normalizedKey[index] ^ 0x5c;
      innerPad[index] = normalizedKey[index] ^ 0x36;
    }

    const message = this.utf8Encode(text);
    const innerInput = new Uint8Array(innerPad.length + message.length);
    innerInput.set(innerPad, 0);
    innerInput.set(message, innerPad.length);
    const innerHash = this.digest(innerInput);

    const outerInput = new Uint8Array(outerPad.length + innerHash.length);
    outerInput.set(outerPad, 0);
    outerInput.set(innerHash, outerPad.length);
    return this.digest(outerInput);
  }

  private digest(bytes: Uint8Array): Uint8Array {
    const words = this.sha256Words(bytes);
    const output = new Uint8Array(32);
    for (let index = 0; index < words.length; index += 1) {
      output[index * 4] = (words[index] >>> 24) & 0xff;
      output[index * 4 + 1] = (words[index] >>> 16) & 0xff;
      output[index * 4 + 2] = (words[index] >>> 8) & 0xff;
      output[index * 4 + 3] = words[index] & 0xff;
    }
    return output;
  }

  private sha256Words(bytes: Uint8Array): Uint32Array {
    const K = [
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ];
    const initialHash = new Uint32Array([
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]);

    const messageLengthBits = bytes.length * 8;
    const paddedLength = (((bytes.length + 9 + 63) >> 6) << 6);
    const padded = new Uint8Array(paddedLength);
    padded.set(bytes, 0);
    padded[bytes.length] = 0x80;

    const high = Math.floor(messageLengthBits / 0x100000000);
    const low = messageLengthBits >>> 0;
    padded[padded.length - 8] = (high >>> 24) & 0xff;
    padded[padded.length - 7] = (high >>> 16) & 0xff;
    padded[padded.length - 6] = (high >>> 8) & 0xff;
    padded[padded.length - 5] = high & 0xff;
    padded[padded.length - 4] = (low >>> 24) & 0xff;
    padded[padded.length - 3] = (low >>> 16) & 0xff;
    padded[padded.length - 2] = (low >>> 8) & 0xff;
    padded[padded.length - 1] = low & 0xff;

    const schedule = new Uint32Array(64);
    for (let chunkOffset = 0; chunkOffset < padded.length; chunkOffset += 64) {
      for (let index = 0; index < 16; index += 1) {
        const byteOffset = chunkOffset + index * 4;
        schedule[index] =
          ((padded[byteOffset] << 24) |
          (padded[byteOffset + 1] << 16) |
          (padded[byteOffset + 2] << 8) |
          padded[byteOffset + 3]) >>> 0;
      }

      for (let index = 16; index < 64; index += 1) {
        const s0 = this.rightRotate(schedule[index - 15], 7) ^
          this.rightRotate(schedule[index - 15], 18) ^
          (schedule[index - 15] >>> 3);
        const s1 = this.rightRotate(schedule[index - 2], 17) ^
          this.rightRotate(schedule[index - 2], 19) ^
          (schedule[index - 2] >>> 10);
        schedule[index] = (schedule[index - 16] + s0 + schedule[index - 7] + s1) >>> 0;
      }

      let a = initialHash[0];
      let b = initialHash[1];
      let c = initialHash[2];
      let d = initialHash[3];
      let e = initialHash[4];
      let f = initialHash[5];
      let g = initialHash[6];
      let h = initialHash[7];

      for (let index = 0; index < 64; index += 1) {
        const s1 = this.rightRotate(e, 6) ^ this.rightRotate(e, 11) ^ this.rightRotate(e, 25);
        const ch = (e & f) ^ (~e & g);
        const temp1 = (h + s1 + ch + K[index] + schedule[index]) >>> 0;
        const s0 = this.rightRotate(a, 2) ^ this.rightRotate(a, 13) ^ this.rightRotate(a, 22);
        const maj = (a & b) ^ (a & c) ^ (b & c);
        const temp2 = (s0 + maj) >>> 0;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) >>> 0;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) >>> 0;
      }

      initialHash[0] = (initialHash[0] + a) >>> 0;
      initialHash[1] = (initialHash[1] + b) >>> 0;
      initialHash[2] = (initialHash[2] + c) >>> 0;
      initialHash[3] = (initialHash[3] + d) >>> 0;
      initialHash[4] = (initialHash[4] + e) >>> 0;
      initialHash[5] = (initialHash[5] + f) >>> 0;
      initialHash[6] = (initialHash[6] + g) >>> 0;
      initialHash[7] = (initialHash[7] + h) >>> 0;
    }

    return initialHash;
  }

  private rightRotate(value: number, amount: number): number {
    return (value >>> amount) | (value << (32 - amount));
  }

  private utf8Encode(text: string): Uint8Array {
    const bytes: number[] = [];
    for (let index = 0; index < text.length; index += 1) {
      let codePoint = text.charCodeAt(index);

      if (codePoint >= 0xd800 && codePoint <= 0xdbff && index + 1 < text.length) {
        const low = text.charCodeAt(index + 1);
        if (low >= 0xdc00 && low <= 0xdfff) {
          codePoint = ((codePoint - 0xd800) << 10) + (low - 0xdc00) + 0x10000;
          index += 1;
        }
      }

      if (codePoint <= 0x7f) {
        bytes.push(codePoint);
      } else if (codePoint <= 0x7ff) {
        bytes.push(0xc0 | (codePoint >> 6));
        bytes.push(0x80 | (codePoint & 0x3f));
      } else if (codePoint <= 0xffff) {
        bytes.push(0xe0 | (codePoint >> 12));
        bytes.push(0x80 | ((codePoint >> 6) & 0x3f));
        bytes.push(0x80 | (codePoint & 0x3f));
      } else {
        bytes.push(0xf0 | (codePoint >> 18));
        bytes.push(0x80 | ((codePoint >> 12) & 0x3f));
        bytes.push(0x80 | ((codePoint >> 6) & 0x3f));
        bytes.push(0x80 | (codePoint & 0x3f));
      }
    }
    return Uint8Array.from(bytes);
  }

  private encodeBase64(bytes: Uint8Array): string {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let output = '';
    for (let index = 0; index < bytes.length; index += 3) {
      const byte1 = bytes[index];
      const byte2 = index + 1 < bytes.length ? bytes[index + 1] : 0;
      const byte3 = index + 2 < bytes.length ? bytes[index + 2] : 0;
      const triplet = (byte1 << 16) | (byte2 << 8) | byte3;
      output += alphabet[(triplet >>> 18) & 0x3f];
      output += alphabet[(triplet >>> 12) & 0x3f];
      output += index + 1 < bytes.length ? alphabet[(triplet >>> 6) & 0x3f] : '=';
      output += index + 2 < bytes.length ? alphabet[triplet & 0x3f] : '=';
    }
    return output;
  }

  private readResponseText(result: Object): string {
    if (typeof result === 'string') {
      return result;
    }

    if (result instanceof ArrayBuffer) {
      return this.utf8Decode(new Uint8Array(result));
    }

    if (ArrayBuffer.isView(result)) {
      const view = result as ArrayBufferView;
      return this.utf8Decode(new Uint8Array(view.buffer, view.byteOffset, view.byteLength));
    }

    return JSON.stringify(result ?? {});
  }

  private utf8Decode(bytes: Uint8Array): string {
    let output = '';
    for (let index = 0; index < bytes.length; ) {
      const first = bytes[index];
      if (first < 0x80) {
        output += String.fromCharCode(first);
        index += 1;
        continue;
      }

      if ((first & 0xe0) === 0xc0 && index + 1 < bytes.length) {
        const codePoint = ((first & 0x1f) << 6) | (bytes[index + 1] & 0x3f);
        output += String.fromCharCode(codePoint);
        index += 2;
        continue;
      }

      if ((first & 0xf0) === 0xe0 && index + 2 < bytes.length) {
        const codePoint = ((first & 0x0f) << 12) |
          ((bytes[index + 1] & 0x3f) << 6) |
          (bytes[index + 2] & 0x3f);
        output += String.fromCharCode(codePoint);
        index += 3;
        continue;
      }

      if ((first & 0xf8) === 0xf0 && index + 3 < bytes.length) {
        const codePoint = ((first & 0x07) << 18) |
          ((bytes[index + 1] & 0x3f) << 12) |
          ((bytes[index + 2] & 0x3f) << 6) |
          (bytes[index + 3] & 0x3f);
        const normalized = codePoint - 0x10000;
        output += String.fromCharCode(0xd800 + (normalized >> 10));
        output += String.fromCharCode(0xdc00 + (normalized & 0x3ff));
        index += 4;
        continue;
      }

      output += '\uFFFD';
      index += 1;
    }
    return output;
  }
}
