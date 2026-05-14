import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';

const PROMISE_STORE_NAME = 'hoson_pref_probe_promise';
const CALLBACK_STORE_NAME = 'hoson_pref_probe_callback';
const SYNC_STORE_NAME = 'hoson_pref_probe_sync';
const PAYLOAD_STORE_NAME = 'hoson_pref_probe_payload';
const LEGACY_STORE_NAME = 'hoson_pref_probe_legacy_store';
const PROBE_STRING_KEY = 'probe_string';
const PROBE_NUMBER_KEY = 'probe_number';
const PAYLOAD_KEY = 'page_strokes_probe-notebook:page-1';

export interface PreferencesSmokeTestReport {
  summary: string;
  lines: string[];
}

type ErrorRecordValue = Object | string | number | boolean | undefined | null;

export async function runPreferencesSmokeTest(context: common.Context): Promise<PreferencesSmokeTestReport> {
  const lines: string[] = [];
  let passed = 0;
  let failed = 0;

  lines.push(`bundle=${getStringField(context, 'bundleName', 'unknown')}`);
  lines.push(`filesDir=${getStringField(context, 'filesDir', 'unavailable')}`);

  await runPromiseProbe(context, lines, () => {
    passed += 1;
  }, () => {
    failed += 1;
  });

  await runCallbackProbe(context, lines, () => {
    passed += 1;
  }, () => {
    failed += 1;
  });

  await runPayloadProbe(context, lines, () => {
    passed += 1;
  }, () => {
    failed += 1;
  });

  await runLegacyStoreProbe(context, lines, () => {
    passed += 1;
  }, () => {
    failed += 1;
  });

  runSyncProbe(context, lines, () => {
    passed += 1;
  }, () => {
    failed += 1;
  });

  const summary = failed === 0 ? `all passed (${passed})` : `passed=${passed} failed=${failed}`;
  logProbe(`summary ${summary}`);

  return {
    summary,
    lines
  };
}

async function runPromiseProbe(
  context: common.Context,
  lines: string[],
  onSuccess: () => void,
  onFailure: () => void
): Promise<void> {
  const label = 'promise';

  try {
    await preferences.removePreferencesFromCache(context, PROMISE_STORE_NAME);
  } catch (_error) {
  }

  try {
    const store = await preferences.getPreferences(context, PROMISE_STORE_NAME);
    await store.clear();
    await store.flush();
    await store.put(PROBE_STRING_KEY, 'ok');
    await store.put(PROBE_NUMBER_KEY, 123);
    await store.flush();
    const stringValue = await store.get(PROBE_STRING_KEY, '') as string;
    const numberValue = Number(await store.get(PROBE_NUMBER_KEY, 0));
    await store.delete(PROBE_STRING_KEY);
    await store.delete(PROBE_NUMBER_KEY);
    await store.flush();
    const deleted = await store.has(PROBE_STRING_KEY);
    onSuccess();
    appendProbeLine(lines, `${label}: ok string=${stringValue} number=${numberValue} deleted=${deleted ? 'false' : 'true'}`);
  } catch (error) {
    onFailure();
    appendProbeLine(lines, `${label}: failed ${stringifyError(error)}`);
  }
}

async function runCallbackProbe(
  context: common.Context,
  lines: string[],
  onSuccess: () => void,
  onFailure: () => void
): Promise<void> {
  const label = 'callback';

  try {
    await removeFromCacheByCallback(context, CALLBACK_STORE_NAME);
  } catch (_error) {
  }

  try {
    const store = await openPreferencesByCallback(context, CALLBACK_STORE_NAME);
    await clearByCallback(store);
    await flushByCallback(store);
    await putByCallback(store, PROBE_STRING_KEY, 'ok');
    await putByCallback(store, PROBE_NUMBER_KEY, 123);
    await flushByCallback(store);
    const stringValue = await getByCallback(store, PROBE_STRING_KEY, '') as string;
    const numberValue = Number(await getByCallback(store, PROBE_NUMBER_KEY, 0));
    await deleteByCallback(store, PROBE_STRING_KEY);
    await deleteByCallback(store, PROBE_NUMBER_KEY);
    await flushByCallback(store);
    const deleted = await hasByCallback(store, PROBE_STRING_KEY);
    onSuccess();
    appendProbeLine(lines, `${label}: ok string=${stringValue} number=${numberValue} deleted=${deleted ? 'false' : 'true'}`);
  } catch (error) {
    onFailure();
    appendProbeLine(lines, `${label}: failed ${stringifyError(error)}`);
  }
}

async function runPayloadProbe(
  context: common.Context,
  lines: string[],
  onSuccess: () => void,
  onFailure: () => void
): Promise<void> {
  const label = 'payload';

  try {
    await preferences.removePreferencesFromCache(context, PAYLOAD_STORE_NAME);
  } catch (_error) {
  }

  try {
    const store = await preferences.getPreferences(context, PAYLOAD_STORE_NAME);
    const payload = buildStrokePayload();
    await store.clear();
    await store.flush();
    await store.put(PAYLOAD_KEY, payload);
    await store.flush();
    const value = await store.get(PAYLOAD_KEY, '[]') as string;
    const matches = value === payload;
    onSuccess();
    appendProbeLine(lines, `${label}: ok key=${PAYLOAD_KEY} bytes=${payload.length} matches=${matches ? 'true' : 'false'}`);
  } catch (error) {
    onFailure();
    appendProbeLine(lines, `${label}: failed ${stringifyError(error)}`);
  }
}

async function runLegacyStoreProbe(
  context: common.Context,
  lines: string[],
  onSuccess: () => void,
  onFailure: () => void
): Promise<void> {
  const label = 'legacy-store';

  try {
    await preferences.removePreferencesFromCache(context, LEGACY_STORE_NAME);
  } catch (_error) {
  }

  try {
    const payload = buildStrokePayload();
    const freshStore = await preferences.getPreferences(context, LEGACY_STORE_NAME);
    await freshStore.clear();
    await freshStore.flush();
    await freshStore.put(PAYLOAD_KEY, payload);
    await freshStore.flush();
    const freshValue = await freshStore.get(PAYLOAD_KEY, '[]') as string;

    const reusedStore = await preferences.getPreferences(context, LEGACY_STORE_NAME);
    await reusedStore.put(PAYLOAD_KEY, payload);
    await reusedStore.flush();
    const reusedValue = await reusedStore.get(PAYLOAD_KEY, '[]') as string;

    await preferences.removePreferencesFromCache(context, LEGACY_STORE_NAME);
    const reopenedStore = await preferences.getPreferences(context, LEGACY_STORE_NAME);
    const reopenedValue = await reopenedStore.get(PAYLOAD_KEY, '[]') as string;

    const freshOk = freshValue === payload;
    const reusedOk = reusedValue === payload;
    const reopenedOk = reopenedValue === payload;
    onSuccess();
    appendProbeLine(
      lines,
      `${label}: ok store=${LEGACY_STORE_NAME} fresh=${freshOk ? 'true' : 'false'} reused=${reusedOk ? 'true' : 'false'} reopened=${reopenedOk ? 'true' : 'false'}`
    );
  } catch (error) {
    onFailure();
    appendProbeLine(lines, `${label}: failed ${stringifyError(error)}`);
  }
}

function runSyncProbe(
  context: common.Context,
  lines: string[],
  onSuccess: () => void,
  onFailure: () => void
): void {
  const label = 'sync';

  try {
    preferences.removePreferencesFromCacheSync(context, SYNC_STORE_NAME);
  } catch (_error) {
  }

  try {
    const store = preferences.getPreferencesSync(context, {
      name: SYNC_STORE_NAME
    });
    store.clearSync();
    store.flushSync();
    store.putSync(PROBE_STRING_KEY, 'ok');
    store.putSync(PROBE_NUMBER_KEY, 123);
    store.flushSync();
    const stringValue = store.getSync(PROBE_STRING_KEY, '') as string;
    const numberValue = Number(store.getSync(PROBE_NUMBER_KEY, 0));
    store.deleteSync(PROBE_STRING_KEY);
    store.deleteSync(PROBE_NUMBER_KEY);
    store.flushSync();
    const deleted = store.hasSync(PROBE_STRING_KEY);
    onSuccess();
    appendProbeLine(lines, `${label}: ok string=${stringValue} number=${numberValue} deleted=${deleted ? 'false' : 'true'}`);
  } catch (error) {
    onFailure();
    appendProbeLine(lines, `${label}: failed ${stringifyError(error)}`);
  }
}

function openPreferencesByCallback(context: common.Context, name: string): Promise<preferences.Preferences> {
  return new Promise((resolve, reject) => {
    preferences.getPreferences(context, name, (error: Object | undefined, store: preferences.Preferences) => {
      if (error) {
        reject(error);
        return;
      }

      resolve(store);
    });
  });
}

function removeFromCacheByCallback(context: common.Context, name: string): Promise<void> {
  return new Promise((resolve, reject) => {
    preferences.removePreferencesFromCache(context, name, (error: Object | undefined) => {
      if (error) {
        reject(error);
        return;
      }

      resolve();
    });
  });
}

function putByCallback(store: preferences.Preferences, key: string, value: preferences.ValueType): Promise<void> {
  return new Promise((resolve, reject) => {
    store.put(key, value, (error: Object | undefined) => {
      if (error) {
        reject(error);
        return;
      }

      resolve();
    });
  });
}

function getByCallback(store: preferences.Preferences, key: string, value: preferences.ValueType): Promise<preferences.ValueType> {
  return new Promise((resolve, reject) => {
    store.get(key, value, (error: Object | undefined, result: preferences.ValueType) => {
      if (error) {
        reject(error);
        return;
      }

      resolve(result);
    });
  });
}

function deleteByCallback(store: preferences.Preferences, key: string): Promise<void> {
  return new Promise((resolve, reject) => {
    store.delete(key, (error: Object | undefined) => {
      if (error) {
        reject(error);
        return;
      }

      resolve();
    });
  });
}

function clearByCallback(store: preferences.Preferences): Promise<void> {
  return new Promise((resolve, reject) => {
    store.clear((error: Object | undefined) => {
      if (error) {
        reject(error);
        return;
      }

      resolve();
    });
  });
}

function flushByCallback(store: preferences.Preferences): Promise<void> {
  return new Promise((resolve, reject) => {
    store.flush((error: Object | undefined) => {
      if (error) {
        reject(error);
        return;
      }

      resolve();
    });
  });
}

function hasByCallback(store: preferences.Preferences, key: string): Promise<boolean> {
  return new Promise((resolve, reject) => {
    store.has(key, (error: Object | undefined, exists: boolean) => {
      if (error) {
        reject(error);
        return;
      }

      resolve(exists);
    });
  });
}

function appendProbeLine(lines: string[], line: string): void {
  lines.push(line);
  logProbe(line);
}

function buildStrokePayload(): string {
  const now = Date.now();
  const strokes = [
    {
      id: 'probe_stroke_1',
      pageId: 'demo-notebook:page-1',
      points: [
        { x: 12, y: 18, t: now, pressure: 0.5 },
        { x: 64, y: 42, t: now + 8, pressure: 0.6 },
        { x: 128, y: 88, t: now + 16, pressure: 0.7 }
      ],
      style: {
        tool: 'pen',
        color: '#111827',
        width: 4,
        opacity: 1
      },
      createdAt: now,
      updatedAt: now + 16
    },
    {
      id: 'probe_stroke_2',
      pageId: 'demo-notebook:page-1',
      points: [
        { x: 200, y: 120, t: now + 24, pressure: 0.4 },
        { x: 244, y: 168, t: now + 32, pressure: 0.5 },
        { x: 288, y: 212, t: now + 40, pressure: 0.6 }
      ],
      style: {
        tool: 'highlighter',
        color: '#F59E0B',
        width: 12,
        opacity: 0.4
      },
      createdAt: now + 24,
      updatedAt: now + 40
    }
  ];

  return JSON.stringify(strokes);
}

function getStringField(context: common.Context, key: string, fallback: string): string {
  const contextRecord = context as unknown as Record<string, ErrorRecordValue>;
  const value = contextRecord[key];
  return typeof value === 'string' && value.length > 0 ? value : fallback;
}

function stringifyError(error: Object): string {
  if (error instanceof Error) {
    if (error.message.length > 0) {
      return error.message;
    }

    return error.name;
  }

  const errorRecord = error as Record<string, ErrorRecordValue>;
  const code = typeof errorRecord.code === 'number' || typeof errorRecord.code === 'string'
    ? `${errorRecord.code}`
    : '';
  const message = typeof errorRecord.message === 'string' ? errorRecord.message : '';

  if (code.length > 0 && message.length > 0) {
    return `${code}: ${message}`;
  }

  if (message.length > 0) {
    return message;
  }

  try {
    const serialized = JSON.stringify(error);
    if (serialized.length > 0 && serialized !== '{}') {
      return serialized;
    }
  } catch (_jsonError) {
  }

  return `${error}`;
}

function logProbe(message: string): void {
  console.info(`[PreferencesProbe] ${message}`);
}
